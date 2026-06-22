# lex-ocpi — Idempotency cache (issue #7)
#
# The OCPI spec requires every request to carry `X-Request-ID`
# (unique per request) and `X-Correlation-ID` (sticky across a
# logical operation). Receivers are supposed to **detect duplicate
# requests** keyed on `X-Request-ID` and reply with the cached
# response rather than re-executing — the standard idempotency
# pattern for safely retrying through a flaky network.
#
# This module wraps `route.dispatch` with that semantics:
#
#   * **First request** with a given key — handler runs, response
#     is cached and returned.
#   * **Duplicate request** — cached response is returned; the
#     handler is NOT re-invoked.
#   * **Concurrent duplicates** — one wins the race and runs the
#     handler; the other(s) poll the `InFlight` marker and pick up
#     the cached response when it lands. Bounded by `max_wait_ms`;
#     on timeout the polling caller falls back to running the
#     handler itself (avoiding indefinite deadlock if the original
#     caller crashed mid-execution).
#   * **TTL expiry** — cache entries drop after `ttl_ms`; the next
#     request re-runs the handler. The default 24h matches OCPI's
#     guidance for replay windows.
#   * **LRU eviction** — capacity-bound; the least-recently-used
#     entry is dropped when a new one would exceed capacity.
#
# Design choices:
#
#   * **`std.conc` actor for the cache state.** Same shape as
#     `commands_async`'s in-flight registry — `Map[Str, CacheSlot]`
#     plus an LRU list. The actor's per-message mutex serialises
#     reservation and store, which is what makes the single-flight
#     race safe.
#
#   * **Poll for in-flight completion, not block.** Sync mailboxes
#     have no `wait`/`notify`; the runner-side actor call would
#     serialise ALL requests through the actor mutex if we
#     processed the user handler inside the actor. Polling lets
#     the handler run *outside* the actor mutex while waiting
#     callers periodically `Lookup` until the result arrives or
#     `max_wait_ms` elapses. Same pattern as
#     `commands_async.wait_for_result`.
#
#   * **SQL-backed variant is a separate PR.** The issue lists
#     `with_idempotency_cache_sql(reg, db)` as the multi-replica
#     production target; that wants `route_io.lex` (the effectful
#     route variant — not yet shipped) and `std.sql`. The in-memory
#     variant covers single-replica deployments today.
#
#   * **Key collision** — the cache key is rendered as
#     `method|path|request_id|from_cc|from_party_id` with `|` as
#     the separator. OCPI paths follow `/ocpi/...` and don't
#     contain pipes; UUID request-ids don't either. Pathological
#     inputs that include `|` could collide — documented but not
#     defended against (would require length-prefixing each field,
#     which is overkill for the production wire shapes).
#
# Effects:
#   * `cache_handler`             — pure transition fn
#   * `new_cache`                 — `[concurrent]`
#   * `try_reserve / store / ...` — `[concurrent]` wrappers
#   * `dispatch_with_cache`       — `[concurrent, time]`

import "std.conc" as conc

import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.time" as time

import "std.tuple" as tuple

import "./envelope" as env

import "./headers" as h

import "./route" as route

# ---- Cache key --------------------------------------------------
type CacheKey = { method :: Str, path :: Str, request_id :: Str, from_cc :: Str, from_party_id :: Str }

# `|` separator — see module-level note on collisions. Length-prefix
# encoding would defend against pathological inputs but the OCPI
# wire shapes don't carry pipes in any of these fields in practice.
fn key_str(k :: CacheKey) -> Str
  examples {
    key_str({ method: "POST", path: "/cdrs", request_id: "r1", from_cc: "NL", from_party_id: "EXM" }) => "POST|/cdrs|r1|NL|EXM"
  }
{
  str.concat(k.method, str.concat("|", str.concat(k.path, str.concat("|", str.concat(k.request_id, str.concat("|", str.concat(k.from_cc, str.concat("|", k.from_party_id))))))))
}

# Derive a key from a parsed request. Returns `None` if the request
# is missing the required `X-Request-ID` header — uncacheable, falls
# through to a normal dispatch.
fn key_from_request(req :: route.OcpiRequest) -> Option[CacheKey] {
  if req.headers.request_id == "" {
    None
  } else {
    Some({ method: req.method, path: req.path, request_id: req.headers.request_id, from_cc: req.headers.from_party.country_code, from_party_id: req.headers.from_party.party_id })
  }
}

# ---- Cache state ------------------------------------------------
#
# Two-level slot type lets the actor distinguish "someone's running
# this" from "this is the cached result" without two separate maps.
type CacheSlot = InFlight | Completed({ response :: env.OcpiResponse, expires_at_ns :: Int })

type CacheState = { entries :: Map[Str, CacheSlot], lru :: List[Str], capacity :: Int }

# ---- Messages + replies -----------------------------------------
type CacheMsg = TryReserve(Str) | Store((Str, env.OcpiResponse, Int)) | Forget(Str) | Lookup((Str, Int)) | Purge(Int)

type CacheReply = Run | Wait | Hit({ response :: env.OcpiResponse }) | Miss | Ack

fn cache_handler(state :: CacheState, msg :: CacheMsg) -> (CacheState, CacheReply) {
  match msg {
    TryReserve(k) => handle_try_reserve(state, k),
    Store(k, r, exp_ns) => (insert_completed(state, k, r, exp_ns), Ack),
    Forget(k) => (remove(state, k), Ack),
    Lookup(k, now_ns) => (state, lookup_reply(state, k, now_ns)),
    Purge(now_ns) => (purge_expired(state, now_ns), Ack),
  }
}

fn handle_try_reserve(state :: CacheState, k :: Str) -> (CacheState, CacheReply) {
  match map.get(state.entries, k) {
    None => (insert_inflight(state, k), Run),
    Some(InFlight) => (state, Wait),
    Some(Completed(c)) => (bump(state, k), Hit({ response: c.response })),
  }
}

# Lookup is the pollers' path. Distinguishes "still in-flight" from
# "cached" from "vanished" (TTL expired or never registered).
fn lookup_reply(state :: CacheState, k :: Str, now_ns :: Int) -> CacheReply {
  match map.get(state.entries, k) {
    None => Miss,
    Some(InFlight) => Wait,
    Some(Completed(c)) => if now_ns >= c.expires_at_ns {
      Miss
    } else {
      Hit({ response: c.response })
    },
  }
}

fn insert_inflight(state :: CacheState, k :: Str) -> CacheState {
  let entries := map.set(state.entries, k, InFlight)
  let lru := list.cons(k, remove_from_list(state.lru, k))
  evict_if_over_capacity({ entries: entries, lru: lru, capacity: state.capacity })
}

fn insert_completed(state :: CacheState, k :: Str, r :: env.OcpiResponse, exp_ns :: Int) -> CacheState {
  let entries := map.set(state.entries, k, Completed({ response: r, expires_at_ns: exp_ns }))
  let lru := list.cons(k, remove_from_list(state.lru, k))
  evict_if_over_capacity({ entries: entries, lru: lru, capacity: state.capacity })
}

fn remove(state :: CacheState, k :: Str) -> CacheState {
  { entries: map.delete(state.entries, k), lru: remove_from_list(state.lru, k), capacity: state.capacity }
}

# Move `k` to the head of the LRU list.
fn bump(state :: CacheState, k :: Str) -> CacheState {
  { entries: state.entries, lru: list.cons(k, remove_from_list(state.lru, k)), capacity: state.capacity }
}

# Drop entries whose `expires_at_ns < now_ns`. In-flight slots are
# kept (they have no expiry until they complete).
fn purge_expired(state :: CacheState, now_ns :: Int) -> CacheState {
  let entries := state.entries
  let kept := list.filter(map.entries(entries), fn (kv :: (Str, CacheSlot)) -> Bool {
    match tuple.snd(kv) {
      InFlight => true,
      Completed(c) => c.expires_at_ns >= now_ns,
    }
  })
  let new_entries := list.fold(kept, map.new(), fn (acc :: Map[Str, CacheSlot], kv :: (Str, CacheSlot)) -> Map[Str, CacheSlot] {
    map.set(acc, tuple.fst(kv), tuple.snd(kv))
  })
  let live_keys := list.map(kept, fn (kv :: (Str, CacheSlot)) -> Str {
    tuple.fst(kv)
  })
  let new_lru := list.filter(state.lru, fn (k :: Str) -> Bool {
    list.fold(live_keys, false, fn (found :: Bool, lk :: Str) -> Bool {
      found or lk == k
    })
  })
  { entries: new_entries, lru: new_lru, capacity: state.capacity }
}

# Evict tails until `map.size(entries) <= capacity`. The LRU list is
# the source of truth for eviction order; oldest entries (tail) go
# first. `capacity <= 0` is treated as "no bound".
fn evict_if_over_capacity(state :: CacheState) -> CacheState {
  if state.capacity <= 0 {
    state
  } else {
    if map.size(state.entries) <= state.capacity {
      state
    } else {
      match last_key(state.lru) {
        None => state,
        Some(k) => evict_if_over_capacity({ entries: map.delete(state.entries, k), lru: remove_from_list(state.lru, k), capacity: state.capacity }),
      }
    }
  }
}

# Helper: drop the first occurrence of `target` from `xs`.
fn remove_from_list(xs :: List[Str], target :: Str) -> List[Str] {
  list.filter(xs, fn (s :: Str) -> Bool {
    s != target
  })
}

fn last_key(xs :: List[Str]) -> Option[Str] {
  list.head(list.reverse(xs))
}

# ---- Spawning ---------------------------------------------------
fn empty_state(capacity :: Int) -> CacheState {
  { entries: map.new(), lru: [], capacity: capacity }
}

fn new_cache(capacity :: Int) -> [concurrent] Actor[CacheState] {
  conc.spawn(empty_state(capacity), cache_handler)
}

# ---- Actor wrappers (thin) -------------------------------------
fn try_reserve(actor :: Actor[CacheState], k :: Str) -> [concurrent] CacheReply {
  conc.ask(actor, TryReserve(k))
}

fn store_response(actor :: Actor[CacheState], k :: Str, r :: env.OcpiResponse, exp_ns :: Int) -> [concurrent] Unit {
  conc.tell(actor, Store(k, r, exp_ns))
}

fn forget(actor :: Actor[CacheState], k :: Str) -> [concurrent] Unit {
  conc.tell(actor, Forget(k))
}

fn lookup(actor :: Actor[CacheState], k :: Str, now_ns :: Int) -> [concurrent] CacheReply {
  conc.ask(actor, Lookup(k, now_ns))
}

fn purge(actor :: Actor[CacheState], now_ns :: Int) -> [concurrent] Unit {
  conc.tell(actor, Purge(now_ns))
}

# ---- Dispatch wrapper ------------------------------------------
#
# Effectful drop-in for `route.dispatch`. Splits into:
#
#   1. Pull the cache key from the request. If absent (no
#      `X-Request-ID`), skip the cache entirely.
#   2. `TryReserve` — atomic in the actor mailbox.
#   3. Branch on the reply:
#      * Hit → return the cached response (handler not invoked).
#      * Run → invoke the handler, Store the response with TTL,
#        return it.
#      * Wait → poll Lookup until Hit, Miss (TTL expired while
#        we were polling), or max_wait_ms elapses. On timeout
#        fall back to running the handler ourselves (avoiding
#        deadlock if the original caller died).
#
# `now_ns` and `timestamp` are caller-supplied to keep the wrapper
# testable without `[time]` for clock advancement; in production
# the transport layer threads `time.mono_ns()` + `time.now_str()`.
type CacheConfig = { ttl_ms :: Int, poll_interval_ms :: Int, max_wait_ms :: Int }

fn default_config() -> CacheConfig {
  { ttl_ms: 24 * 60 * 60 * 1000, poll_interval_ms: 50, max_wait_ms: 5000 }
}

fn dispatch_with_cache(reg :: route.Registry, cache :: Actor[CacheState], cfg :: CacheConfig, req :: route.OcpiRequest, timestamp :: Str) -> [concurrent, time] env.OcpiResponse {
  match key_from_request(req) {
    None => route.dispatch(reg, req, timestamp),
    Some(k) => {
      let key := key_str(k)
      dispatch_branch(reg, cache, cfg, req, timestamp, key)
    },
  }
}

fn dispatch_branch(reg :: route.Registry, cache :: Actor[CacheState], cfg :: CacheConfig, req :: route.OcpiRequest, timestamp :: Str, key :: Str) -> [concurrent, time] env.OcpiResponse {
  match try_reserve(cache, key) {
    Hit(h) => h.response,
    Run => run_and_cache(reg, cache, cfg, req, timestamp, key),
    Wait => wait_or_fallback(reg, cache, cfg, req, timestamp, key),
    Miss => run_and_cache(reg, cache, cfg, req, timestamp, key),
    Ack => run_and_cache(reg, cache, cfg, req, timestamp, key),
  }
}

fn run_and_cache(reg :: route.Registry, cache :: Actor[CacheState], cfg :: CacheConfig, req :: route.OcpiRequest, timestamp :: Str, key :: Str) -> [concurrent, time] env.OcpiResponse {
  let resp := route.dispatch(reg, req, timestamp)
  let expires_at_ns := time.mono_ns() + cfg.ttl_ms * 1000000
  let __lex_discard_1 := store_response(cache, key, resp, expires_at_ns)
  resp
}

# Poll the cache for completion. On timeout, we clear the in-flight
# marker (the original caller is presumed dead) and run the handler
# ourselves. Same shape as `commands_async.wait_for_result`.
fn wait_or_fallback(reg :: route.Registry, cache :: Actor[CacheState], cfg :: CacheConfig, req :: route.OcpiRequest, timestamp :: Str, key :: Str) -> [concurrent, time] env.OcpiResponse {
  let deadline_ns := time.mono_ns() + cfg.max_wait_ms * 1000000
  poll_for_completion(reg, cache, cfg, req, timestamp, key, deadline_ns)
}

fn poll_for_completion(reg :: route.Registry, cache :: Actor[CacheState], cfg :: CacheConfig, req :: route.OcpiRequest, timestamp :: Str, key :: Str, deadline_ns :: Int) -> [concurrent, time] env.OcpiResponse {
  match lookup(cache, key, time.mono_ns()) {
    Hit(h) => h.response,
    Miss => {
      let __lex_discard_2 := forget(cache, key)
      run_and_cache(reg, cache, cfg, req, timestamp, key)
    },
    Wait => if time.mono_ns() >= deadline_ns {
      let __lex_discard_3 := forget(cache, key)
      run_and_cache(reg, cache, cfg, req, timestamp, key)
    } else {
      let __lex_discard_4 := time.sleep_ms(cfg.poll_interval_ms)
      poll_for_completion(reg, cache, cfg, req, timestamp, key, deadline_ns)
    },
    Run => run_and_cache(reg, cache, cfg, req, timestamp, key),
    Ack => run_and_cache(reg, cache, cfg, req, timestamp, key),
  }
}

