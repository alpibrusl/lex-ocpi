# lex-ocpi — SQL-backed idempotency cache tests (issue #7)
#
# Live-database integration tests need a SQLite/Postgres handle which
# `lex ci` doesn't provide. What's testable purely:
#
#   * config defaults match the spec's guidance
#   * table_name() is the canonical identifier (so SQL strings
#     line up with whatever migration tooling references)
#   * stringify_response round-trips through env.parse — the
#     serializer doesn't drift from the parser
#   * decode_existing's three-branch logic (stale / completed /
#     inflight) over a known row + clock
#
# Round-trip tests against a real SQLite handle (`setup` + `try_reserve`
# + concurrent claim) belong in the conformance harness (#10) once the
# `[sql]` test runner lands.

import "std.list" as list
import "std.str"  as str

import "lex-schema/json_value" as jv

import "../src/envelope"        as env
import "../src/idempotency_sql" as isql

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, want)
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, got))
  }
}

# ---- Config ----------------------------------------------------

fn test_default_config() -> Result[Unit, Str] {
  let c := isql.default_config()
  if c.ttl_ms == 24 * 60 * 60 * 1000
     and c.poll_interval_ms == 50
     and c.max_wait_ms == 5000 {
    pass()
  } else {
    fail("default config values drifted")
  }
}

fn test_table_name_stable() -> Result[Unit, Str] {
  assert_eq_str("ocpi_idempotency_cache", isql.table_name(), "table name")
}

# ---- stringify_response round-trip ---------------------------
#
# stringify + env.parse must be inverses on a representative
# envelope. Catches drift between the encoder and the existing
# decoder (env.parse).

fn sample_response() -> env.OcpiResponse {
  { data:           JObj([("id", JStr("L1"))]),
    status_code:    1000,
    status_message: "",
    timestamp:      "2026-05-17T09:00:00Z" }
}

fn test_stringify_parse_round_trip() -> Result[Unit, Str] {
  let r := sample_response()
  let s := isql.stringify_response(r)
  match env.parse(s) {
    Err(e) => fail(str.concat("env.parse failed: ", e.message)),
    Ok(r2) => if r2.status_code == r.status_code
                 and r2.status_message == r.status_message
                 and r2.timestamp == r.timestamp {
                pass()
              } else {
                fail("round-trip lost a field")
              },
  }
}

fn test_stringify_response_carries_status_code() -> Result[Unit, Str] {
  let s := isql.stringify_response(sample_response())
  if str.contains(s, "\"status_code\":1000") { pass() }
  else { fail("status_code missing from serialised envelope") }
}

# ---- decode_existing branches --------------------------------

fn test_decode_existing_stale_inflight_is_wait() -> Result[Unit, Str] {
  let row := { status: "inflight", response_json: None,
               expires_at_ms: 1000 }
  match isql.decode_existing(row, 2000) {
    SqlReserveWait => pass(),
    _              => fail("expected SqlReserveWait for stale inflight"),
  }
}

fn test_decode_existing_fresh_inflight_is_wait() -> Result[Unit, Str] {
  let row := { status: "inflight", response_json: None,
               expires_at_ms: 5000 }
  match isql.decode_existing(row, 2000) {
    SqlReserveWait => pass(),
    _              => fail("expected SqlReserveWait for fresh inflight"),
  }
}

fn test_decode_existing_completed_is_hit() -> Result[Unit, Str] {
  let r := sample_response()
  let row := { status: "completed",
               response_json: Some(isql.stringify_response(r)),
               expires_at_ms: 5000 }
  match isql.decode_existing(row, 2000) {
    SqlReserveHit(got) => assert_true(got.status_code == r.status_code,
                                       "status_code round-tripped"),
    _                  => fail("expected SqlReserveHit for fresh completed"),
  }
}

fn test_decode_existing_expired_completed_is_wait() -> Result[Unit, Str] {
  let r := sample_response()
  let row := { status: "completed",
               response_json: Some(isql.stringify_response(r)),
               expires_at_ms: 1000 }
  match isql.decode_existing(row, 2000) {
    SqlReserveWait => pass(),
    _              => fail("expected SqlReserveWait for expired completed"),
  }
}

fn test_decode_existing_completed_null_body_is_wait() -> Result[Unit, Str] {
  # Defensive case: status=completed but response_json is NULL.
  # Shouldn't happen in normal operation but the decoder must be
  # total and not crash.
  let row := { status: "completed", response_json: None,
               expires_at_ms: 5000 }
  match isql.decode_existing(row, 2000) {
    SqlReserveWait => pass(),
    _              => fail("expected SqlReserveWait when response_json missing"),
  }
}

# ---- Suite + runner ------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_default_config(),
    test_table_name_stable(),
    test_stringify_parse_round_trip(),
    test_stringify_response_carries_status_code(),
    test_decode_existing_stale_inflight_is_wait(),
    test_decode_existing_fresh_inflight_is_wait(),
    test_decode_existing_completed_is_hit(),
    test_decode_existing_expired_completed_is_wait(),
    test_decode_existing_completed_null_body_is_wait(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}
