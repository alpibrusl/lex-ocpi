# lex-ocpi — client request-builder tests
#
# Pure tests only — we exercise `base_request`, `with_token`,
# `with_party_routing`, `with_json_body`, never `client.send`
# (which would need `[net]`). Send-loop tests would need a fake
# HTTP server fixture; deferred.

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

import "../src/client"   as client
import "../src/envelope" as env
import "../src/headers"  as h
import "../src/party"    as party

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else {
    fail(str.concat(label, str.concat(": want=", str.concat(want,
      str.concat(" got=", got)))))
  }
}

# ---- base_request -----------------------------------------------

fn test_base_request_method() -> Result[Unit, Str] {
  let r := client.base_request("GET", "https://example.com/x")
  assert_eq_str("GET", r.method, "method")
}

fn test_base_request_url() -> Result[Unit, Str] {
  let r := client.base_request("POST", "https://example.com/x")
  assert_eq_str("https://example.com/x", r.url, "url")
}

# ---- with_token sets Authorization ------------------------------

fn test_with_token() -> Result[Unit, Str] {
  let r := client.with_token(
             client.base_request("GET", "https://example.com/x"),
             "ABC==")
  match map.get(r.headers, h.h_authorization()) {
    None    => fail("authorization header missing"),
    Some(v) => assert_eq_str("Token ABC==", v, "authorization"),
  }
}

# ---- with_party_routing sets all four headers --------------------

fn test_with_party_routing() -> Result[Unit, Str] {
  let r := client.with_party_routing(
             client.base_request("GET", "https://example.com/x"),
             party.new("NL", "TNM"),
             party.new("DE", "BMW"))
  let from_cc := match map.get(r.headers, h.h_from_country_code()) {
    None    => "",
    Some(v) => v,
  }
  let to_pid := match map.get(r.headers, h.h_to_party_id()) {
    None    => "",
    Some(v) => v,
  }
  if from_cc == "NL" and to_pid == "BMW" { pass() }
  else { fail("party routing headers missing or wrong") }
}

# ---- with_json_body sets Content-Type and body -----------------

fn test_with_json_body_sets_ct() -> Result[Unit, Str] {
  let r := client.with_json_body(
             client.base_request("PUT", "https://example.com/x"),
             "{\"hello\":\"world\"}")
  match map.get(r.headers, "content-type") {
    None    => fail("content-type missing"),
    Some(v) => assert_eq_str("application/json", v, "content-type"),
  }
}

# ---- with_request_id + with_correlation_id ---------------------

fn test_with_request_id() -> Result[Unit, Str] {
  let r := client.with_request_id(
             client.base_request("GET", "https://example.com/x"),
             "req-1")
  match map.get(r.headers, h.h_request_id()) {
    None    => fail("X-Request-ID missing"),
    Some(v) => assert_eq_str("req-1", v, "X-Request-ID"),
  }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_base_request_method(),
    test_base_request_url(),
    test_with_token(),
    test_with_party_routing(),
    test_with_json_body_sets_ct(),
    test_with_request_id(),
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
