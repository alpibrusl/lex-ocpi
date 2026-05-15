# lex-ocpi — route dispatch tests

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/envelope" as env
import "../src/error"    as oe
import "../src/headers"  as headers
import "../src/party"    as party
import "../src/route"    as route
import "../src/status"   as status

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- Test fixtures ----------------------------------------------

fn empty_headers() -> headers.OcpiHeaders {
  headers.new("", "", "",
    party.new("", ""), party.new("", ""))
}

fn empty_req(method :: Str, module :: Str) -> route.OcpiRequest {
  route.request(method, module, str.concat("/", module),
    map.empty(), map.empty(), empty_headers(), JNull)
}

fn req_with_body(
  method :: Str,
  module :: Str,
  body   :: jv.Json
) -> route.OcpiRequest {
  route.request(method, module, str.concat("/", module),
    map.empty(), map.empty(), empty_headers(), body)
}

fn ts() -> Str { "2026-05-15T10:00:00Z" }

# ---- Handlers ----------------------------------------------------

fn hello_handler(_req :: route.OcpiRequest) -> route.HandlerResult {
  route.ok(JObj([("hello", JStr("world"))]))
}

fn error_handler(_req :: route.OcpiRequest) -> route.HandlerResult {
  route.fail(oe.unknown_location("loc-xyz"))
}

# ---- Tests -------------------------------------------------------

fn test_dispatch_known_route() -> Result[Unit, Str] {
  let reg := route.handler(route.new(), route.get(), "locations", hello_handler)
  let res := route.dispatch(reg, empty_req(route.get(), "locations"), ts())
  assert_eq_int(1000, res.status_code, "ok")
}

fn test_dispatch_unknown_route() -> Result[Unit, Str] {
  let reg := route.handler(route.new(), route.get(), "locations", hello_handler)
  let res := route.dispatch(reg, empty_req(route.get(), "sessions"), ts())
  assert_eq_int(2000, res.status_code, "unknown should return generic client error")
}

fn test_dispatch_method_mismatch() -> Result[Unit, Str] {
  let reg := route.handler(route.new(), route.get(), "locations", hello_handler)
  let res := route.dispatch(reg, empty_req(route.post(), "locations"), ts())
  if res.status_code != 1000 { pass() }
  else { fail("POST should not match a GET-only route") }
}

fn test_handler_returns_error() -> Result[Unit, Str] {
  let reg := route.handler(route.new(), route.get(), "locations", error_handler)
  let res := route.dispatch(reg, empty_req(route.get(), "locations"), ts())
  assert_eq_int(2003, res.status_code, "unknown_location")
}

# ---- Validator integration --------------------------------------

fn always_fail_validator(_j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  Err([e.error("field", e.code_min_len(), "must not be empty")])
}

fn always_pass_validator(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  Ok(j)
}

fn test_validator_short_circuits() -> Result[Unit, Str] {
  let reg := route.handler_with_schema(route.new(),
    route.post(), "locations", always_fail_validator, hello_handler)
  let res := route.dispatch(reg,
    req_with_body(route.post(), "locations", JObj([])), ts())
  assert_eq_int(2001, res.status_code, "validator failure should return 2001")
}

fn test_validator_passes_through() -> Result[Unit, Str] {
  let reg := route.handler_with_schema(route.new(),
    route.post(), "locations", always_pass_validator, hello_handler)
  let res := route.dispatch(reg,
    req_with_body(route.post(), "locations", JObj([])), ts())
  assert_eq_int(1000, res.status_code, "validator pass should reach handler")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_dispatch_known_route(),
    test_dispatch_unknown_route(),
    test_dispatch_method_mismatch(),
    test_handler_returns_error(),
    test_validator_short_circuits(),
    test_validator_passes_through(),
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
