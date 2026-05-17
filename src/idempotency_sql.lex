# lex-ocpi — SQL-backed idempotency cache (issue #7 multi-replica variant)
#
# The in-memory variant (`src/idempotency.lex`) holds cache state in a
# `std.conc` actor: fine for a single replica, evicted on process
# restart, not shared across replicas. This module persists the cache
# to a SQL table with the same dedup semantics, so:
#
#   * multiple replicas behind a load balancer collapse onto the same
#     cache and de-duplicate cross-replica retries,
#   * the cache survives a process restart — a retry an hour later
#     still hits a cached response (subject to TTL).
#
# Concurrency model:
#
#   * **Atomic claim** via `INSERT ... ON CONFLICT (cache_key) DO
#     NOTHING`. Exactly one replica's INSERT changes a row; everyone
#     else's is a no-op. We check `rows_affected` to decide who won.
#   * **Coalescing** for concurrent duplicates: losers `SELECT` the
#     current state. If they see an inflight row, they poll until it
#     completes or `max_wait_ms` elapses.
#   * **Stuck-writer recovery**: if a writer dies mid-execution, its
#     inflight row's `expires_at_ms` eventually lapses. The next
#     reader treats a stale-and-expired inflight as not-cached and
#     re-claims it (via `forget` + retry).
#   * **Background sweep** via `purge_expired(db, now_ms)`. Optional;
#     the table grows unbounded without it, but correctness is
#     unaffected because every read predicate filters on
#     `expires_at_ms > now_ms`.
#
# Schema (idempotent; bootstrap with `setup(db)`):
#
#   CREATE TABLE IF NOT EXISTS ocpi_idempotency_cache (
#     cache_key       TEXT     PRIMARY KEY,
#     status          TEXT     NOT NULL,     -- 'inflight' | 'completed'
#     response_json   TEXT,                   -- NULL while inflight
#     expires_at_ms   BIGINT   NOT NULL,     -- Unix-ms (time.now_ms()-shaped)
#     created_at_ms   BIGINT   NOT NULL
#   );
#   CREATE INDEX IF NOT EXISTS idx_ocpi_idempotency_expires
#     ON ocpi_idempotency_cache (expires_at_ms);
#
# Why epoch-ms (Int) over ISO-8601 (Str): comparable math without a
# date-parse primitive, and `time.now_ms()` (lex 0.9.2+) gives us
# the wall-clock value directly.
#
# Effects:
#   * `setup`, `try_reserve`, `store_completed`, `forget`,
#     `purge_expired`, `inspect_existing` — `[sql]`
#   * `dispatch_with_cache_sql` — `[io, time, sql]`

import "std.list" as list
import "std.sql"  as sql
import "std.str"  as str
import "std.int"  as int
import "std.time" as time

import "lex-schema/json_value" as jv

import "./envelope"    as env
import "./idempotency" as imem
import "./route"       as route
import "./route_io"    as rio

# ---- Config ----------------------------------------------------

type SqlCacheConfig = {
  ttl_ms           :: Int,
  poll_interval_ms :: Int,
  max_wait_ms      :: Int,
}

# 24h TTL matches the spec's replay window; 50ms poll + 5s
# max-wait are conservative defaults for the single-flight path.
fn default_config() -> SqlCacheConfig {
  { ttl_ms: 24 * 60 * 60 * 1000, poll_interval_ms: 50, max_wait_ms: 5000 }
}

fn table_name() -> Str {
  "ocpi_idempotency_cache"
}

# ---- Schema bootstrap ------------------------------------------

fn setup(db :: sql.Db) -> [sql] Result[Unit, Str] {
  let t := table_name()
  let create_sql := str.concat(
    "CREATE TABLE IF NOT EXISTS ",
    str.concat(t,
      " (cache_key TEXT PRIMARY KEY, status TEXT NOT NULL, response_json TEXT, expires_at_ms BIGINT NOT NULL, created_at_ms BIGINT NOT NULL)"))
  match sql.exec(db, create_sql, []) {
    Err(e) => Err(e.message),
    Ok(_)  => {
      let idx_sql := str.concat(
        "CREATE INDEX IF NOT EXISTS idx_ocpi_idempotency_expires ON ",
        str.concat(t, " (expires_at_ms)"))
      match sql.exec(db, idx_sql, []) {
        Err(e) => Err(e.message),
        Ok(_)  => Ok(()),
      }
    },
  }
}

# ---- Reserve outcome --------------------------------------------

type SqlReserve =
    SqlReserveRun                              # we claimed it; caller runs the handler
  | SqlReserveHit(env.OcpiResponse)            # cached response; return it directly
  | SqlReserveWait                              # someone else holds the inflight slot

# ---- Atomic reserve --------------------------------------------
#
# Step 1: try to INSERT a fresh inflight row. ON CONFLICT DO NOTHING
# means contention is a no-op, not an error — `rows_affected` tells
# us who won.
# Step 2: if we didn't win (rows_affected = 0), SELECT the existing
# row and decide based on its state + freshness.
#
# A stale inflight row (expires_at_ms <= now_ms) is treated as
# free — the caller will time-out the poll and forge ahead.

fn try_reserve(
  db             :: sql.Db,
  key            :: Str,
  now_ms         :: Int,
  expires_at_ms  :: Int
) -> [sql] SqlReserve {
  let t := table_name()
  let ins_sql := str.concat(
    "INSERT INTO ", str.concat(t,
      " (cache_key, status, response_json, expires_at_ms, created_at_ms) VALUES ($1, 'inflight', NULL, $2, $3) ON CONFLICT (cache_key) DO NOTHING"))
  match sql.exec(db, ins_sql, [PStr(key), PInt(expires_at_ms), PInt(now_ms)]) {
    Err(_) => SqlReserveWait,
    Ok(n)  => if n == 1 {
                SqlReserveRun
              } else {
                inspect_existing(db, key, now_ms)
              },
  }
}

fn inspect_existing(
  db       :: sql.Db,
  key      :: Str,
  now_ms   :: Int
) -> [sql] SqlReserve {
  let t := table_name()
  let sel_sql := str.concat(
    "SELECT status, response_json, expires_at_ms FROM ",
    str.concat(t, " WHERE cache_key = $1"))
  let raw :: Result[List[{ status :: Str, response_json :: Option[Str], expires_at_ms :: Int }], SqlError] :=
    sql.query(db, sel_sql, [PStr(key)])
  match raw {
    Err(_)   => SqlReserveWait,
    Ok(rows) => match list.head(rows) {
      None    => SqlReserveWait,           # row vanished between INSERT and SELECT (rare)
      Some(r) => decode_existing(r, now_ms),
    },
  }
}

fn decode_existing(
  r       :: { status :: Str, response_json :: Option[Str], expires_at_ms :: Int },
  now_ms  :: Int
) -> SqlReserve {
  # Stale: TTL elapsed; treat as not-cached. Caller polls and the
  # poll loop will eventually forget+retry.
  if r.expires_at_ms <= now_ms {
    SqlReserveWait
  } else { if r.status == "completed" {
    match r.response_json {
      None    => SqlReserveWait,           # broken row (NULL response on completed) — defensive
      Some(s) => match env.parse(s) {
        Err(_) => SqlReserveWait,
        Ok(resp) => SqlReserveHit(resp),
      },
    }
  } else {
    SqlReserveWait                          # 'inflight' + not stale — another replica is running
  } }
}

# ---- Completion store ------------------------------------------

fn store_completed(
  db   :: sql.Db,
  key  :: Str,
  resp :: env.OcpiResponse
) -> [sql] Result[Unit, Str] {
  let t := table_name()
  let upd_sql := str.concat(
    "UPDATE ", str.concat(t,
      " SET status = 'completed', response_json = $1 WHERE cache_key = $2"))
  let resp_str := stringify_response(resp)
  match sql.exec(db, upd_sql, [PStr(resp_str), PStr(key)]) {
    Err(e) => Err(e.message),
    Ok(_)  => Ok(()),
  }
}

# Encode an OcpiResponse back to its wire JSON. Mirrors `env.parse`
# which is the inverse. We don't depend on `env.stringify` existing
# (it might or might not) — building the JObj here is one line and
# locks the shape next to its inverse.
fn stringify_response(r :: env.OcpiResponse) -> Str {
  jv.stringify(JObj([
    ("data",           r.data),
    ("status_code",    JInt(r.status_code)),
    ("status_message", JStr(r.status_message)),
    ("timestamp",      JStr(r.timestamp)),
  ]))
}

fn forget(db :: sql.Db, key :: Str) -> [sql] Result[Unit, Str] {
  let t := table_name()
  let del_sql := str.concat(
    "DELETE FROM ", str.concat(t, " WHERE cache_key = $1"))
  match sql.exec(db, del_sql, [PStr(key)]) {
    Err(e) => Err(e.message),
    Ok(_)  => Ok(()),
  }
}

# Drop every row whose `expires_at_ms < now_ms`. Optional background
# sweeper; correctness doesn't depend on it (reads filter on
# `expires_at_ms > now_ms` anyway), but unbounded growth without
# this would eventually hurt INSERT/SELECT performance.
fn purge_expired(db :: sql.Db, now_ms :: Int) -> [sql] Result[Int, Str] {
  let t := table_name()
  let del_sql := str.concat(
    "DELETE FROM ", str.concat(t, " WHERE expires_at_ms < $1"))
  match sql.exec(db, del_sql, [PInt(now_ms)]) {
    Err(e) => Err(e.message),
    Ok(n)  => Ok(n),
  }
}

# ---- Dispatch wrapper ------------------------------------------
#
# Mirrors `idempotency.dispatch_with_cache` but wraps `route_io`
# (effectful registry) and persists to a SQL table.
#
# Skips the cache entirely if the request has no `X-Request-ID`
# (uncacheable per OCPI §10.5 — cache key requires the request-id).
# Falls through to `rio.dispatch` unchanged in that case.

fn dispatch_with_cache_sql(
  reg       :: rio.IoRegistry,
  db        :: sql.Db,
  cfg       :: SqlCacheConfig,
  req       :: route.OcpiRequest,
  timestamp :: Str
) -> [io, time, sql] env.OcpiResponse {
  match imem.key_from_request(req) {
    None    => rio.dispatch(reg, req, timestamp),
    Some(k) => {
      let key := imem.key_str(k)
      dispatch_branch_sql(reg, db, cfg, req, timestamp, key)
    },
  }
}

fn dispatch_branch_sql(
  reg       :: rio.IoRegistry,
  db        :: sql.Db,
  cfg       :: SqlCacheConfig,
  req       :: route.OcpiRequest,
  timestamp :: Str,
  key       :: Str
) -> [io, time, sql] env.OcpiResponse {
  let now := time.now_ms()
  let expires_at := now + cfg.ttl_ms
  match try_reserve(db, key, now, expires_at) {
    SqlReserveHit(r) => r,
    SqlReserveRun    => run_and_store(reg, db, req, timestamp, key),
    SqlReserveWait   => wait_or_fallback(reg, db, cfg, req, timestamp, key),
  }
}

# Run the handler, then `store_completed` the response. The store
# failure is swallowed deliberately — the response IS valid; we'd
# rather return it than fail just because we couldn't cache.
fn run_and_store(
  reg       :: rio.IoRegistry,
  db        :: sql.Db,
  req       :: route.OcpiRequest,
  timestamp :: Str,
  key       :: Str
) -> [io, time, sql] env.OcpiResponse {
  let resp := rio.dispatch(reg, req, timestamp)
  let _ := store_completed(db, key, resp)
  resp
}

# Poll until the inflight row completes or `max_wait_ms` elapses.
# Same shape as the in-memory variant's `poll_for_completion`.
fn wait_or_fallback(
  reg       :: rio.IoRegistry,
  db        :: sql.Db,
  cfg       :: SqlCacheConfig,
  req       :: route.OcpiRequest,
  timestamp :: Str,
  key       :: Str
) -> [io, time, sql] env.OcpiResponse {
  let deadline_ns := time.mono_ns() + cfg.max_wait_ms * 1_000_000
  poll_loop_sql(reg, db, cfg, req, timestamp, key, deadline_ns)
}

fn poll_loop_sql(
  reg         :: rio.IoRegistry,
  db          :: sql.Db,
  cfg         :: SqlCacheConfig,
  req         :: route.OcpiRequest,
  timestamp   :: Str,
  key         :: Str,
  deadline_ns :: Int
) -> [io, time, sql] env.OcpiResponse {
  let now := time.now_ms()
  match inspect_existing(db, key, now) {
    SqlReserveHit(r) => r,
    SqlReserveRun    => run_and_store(reg, db, req, timestamp, key),
    SqlReserveWait   => if time.mono_ns() >= deadline_ns {
                         # Original writer presumed dead. Clear and run.
                         let _ := forget(db, key)
                         run_and_store(reg, db, req, timestamp, key)
                       } else {
                         let _ := time.sleep_ms(cfg.poll_interval_ms)
                         poll_loop_sql(reg, db, cfg, req, timestamp, key, deadline_ns)
                       },
  }
}
