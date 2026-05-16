# lex-ocpi — envelope encode / parse tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "../src/envelope" as env
import "../src/status"   as status

# ---- Test scaffolding --------------------------------------------

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() }
  else { fail(str.concat(label,
    str.concat(": want=", str.concat(want, str.concat(" got=", got))))) }
}

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() }
  else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- Encode -----------------------------------------------------

fn test_encode_success_empty() -> Result[Unit, Str] {
  let r := env.ok_empty("2026-05-15T10:00:00Z")
  let want := "{\"data\":null,\"status_code\":1000,\"timestamp\":\"2026-05-15T10:00:00Z\"}"
  assert_eq_str(want, env.encode(r), "encode_success_empty")
}

fn test_encode_success_with_data() -> Result[Unit, Str] {
  let r := env.ok(JObj([("hello", JStr("world"))]), "2026-05-15T10:00:00Z")
  let want := "{\"data\":{\"hello\":\"world\"},\"status_code\":1000,\"timestamp\":\"2026-05-15T10:00:00Z\"}"
  assert_eq_str(want, env.encode(r), "encode_success_with_data")
}

fn test_encode_failure() -> Result[Unit, Str] {
  let r := env.fail(status.unknown_location(), "Unknown Location",
    "2026-05-15T10:00:00Z")
  let want := "{\"data\":null,\"status_code\":2003,\"status_message\":\"Unknown Location\",\"timestamp\":\"2026-05-15T10:00:00Z\"}"
  assert_eq_str(want, env.encode(r), "encode_failure")
}

# ---- Parse ------------------------------------------------------

fn test_parse_success() -> Result[Unit, Str] {
  let raw := "{\"data\":null,\"status_code\":1000,\"timestamp\":\"2026-05-15T10:00:00Z\"}"
  match env.parse(raw) {
    Err(e) => fail(str.concat("parse_success: ", e.message)),
    Ok(r)  => assert_eq_int(1000, r.status_code, "status_code"),
  }
}

fn test_parse_failure_carries_message() -> Result[Unit, Str] {
  let raw := "{\"data\":null,\"status_code\":2003,\"status_message\":\"oops\",\"timestamp\":\"2026-05-15T10:00:00Z\"}"
  match env.parse(raw) {
    Err(e) => fail(str.concat("parse_failure: ", e.message)),
    Ok(r)  => assert_eq_str("oops", r.status_message, "status_message"),
  }
}

fn test_parse_invalid_json() -> Result[Unit, Str] {
  match env.parse("not json") {
    Err(_) => pass(),
    Ok(_)  => fail("invalid JSON should have errored"),
  }
}

fn test_parse_missing_code() -> Result[Unit, Str] {
  match env.parse("{\"timestamp\":\"x\"}") {
    Err(_) => pass(),
    Ok(_)  => fail("missing status_code should have errored"),
  }
}

# ---- Round-trip --------------------------------------------------

fn test_round_trip() -> Result[Unit, Str] {
  let original := env.ok(JList([JStr("a"), JStr("b")]), "2026-05-15T10:00:00Z")
  match env.parse(env.encode(original)) {
    Err(e) => fail(str.concat("round-trip: ", e.message)),
    Ok(r)  => assert_eq_int(1000, r.status_code, "round-trip status_code"),
  }
}

# ---- Predicates --------------------------------------------------

fn test_is_success() -> Result[Unit, Str] {
  let r := env.ok_empty("ts")
  assert_true(env.is_success(r), "ok_empty should be a success")
}

fn test_is_client_error() -> Result[Unit, Str] {
  let r := env.fail(status.unknown_location(), "x", "ts")
  assert_true(env.is_client_error(r), "2003 should be a client error")
}

fn test_is_server_error() -> Result[Unit, Str] {
  let r := env.fail(status.server_error(), "x", "ts")
  assert_true(env.is_server_error(r), "3000 should be a server error")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_encode_success_empty(),
    test_encode_success_with_data(),
    test_encode_failure(),
    test_parse_success(),
    test_parse_failure_carries_message(),
    test_parse_invalid_json(),
    test_parse_missing_code(),
    test_round_trip(),
    test_is_success(),
    test_is_client_error(),
    test_is_server_error(),
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
