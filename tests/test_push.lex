# lex-ocpi — Push fanout tests (issue #5)
#
# Covers the pure surface of `src/push.lex`:
#
#   - `push_method(kind)` across all 8 PushKind variants — each
#     variant maps to the spec's (method) tuple.
#   - `push_url(base, kind)` across all 8 variants — each maps to
#     the spec's (path) shape including the {country_code}/{party_id}
#     prefix on the multi-tenant routes.
#   - `push_body(kind)` returns the embedded `body :: jv.Json`
#     verbatim (the encoder is transparent — no re-shaping).
#   - URL helpers (`location_url`, `evse_url`, `connector_url`,
#     `session_url`, `token_url`) round-trip example inputs to
#     concrete spec-shaped URLs.
#   - `build_request(...)` — assembles the right method + URL +
#     OCPI headers (Authorization token + from/to party tuples) +
#     JSON body. We assert on the request shape without a live
#     HTTP target (the retry loop + transport tests live in
#     `tests/test_retry.lex` and the conformance harness — #10).
#
# Live-loop tests (fake 3-eMSP fanout, one peer 5xx-ing, etc.) are
# deferred to the conformance harness in issue #10. The retry path
# is exercised by `tests/test_retry.lex` already.

import "std.list" as list

import "std.map" as map

import "std.str" as str

import "lex-schema/json_value" as jv

import "../src/push" as push

import "../src/party" as party

import "../src/client" as client

import "../src/headers" as h

# ---- Test plumbing ----------------------------------------------
fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b {
    pass()
  } else {
    fail(label)
  }
}

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got {
    pass()
  } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, want)
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, got))
  }
}

# ---- Fixtures ---------------------------------------------------
fn base() -> Str {
  "https://emsp.example/ocpi/2.2.1"
}

fn b230() -> Str {
  "https://emsp.example/ocpi/2.3.0"
}

fn empty_body() -> jv.Json {
  JNull
}

fn loc_put(loc_id :: Str) -> push.PushKind {
  LocationPut({ country_code: "NL", party_id: "TNM", location_id: loc_id, body: empty_body() })
}

fn loc_patch(loc_id :: Str, body :: jv.Json) -> push.PushKind {
  LocationPatch({ country_code: "NL", party_id: "TNM", location_id: loc_id, body: body })
}

fn evse_patch(loc_id :: Str, evse :: Str, body :: jv.Json) -> push.PushKind {
  EvsePatch({ country_code: "NL", party_id: "TNM", location_id: loc_id, evse_uid: evse, body: body })
}

fn conn_patch(loc_id :: Str, evse :: Str, conn :: Str, body :: jv.Json) -> push.PushKind {
  ConnectorPatch({ country_code: "NL", party_id: "TNM", location_id: loc_id, evse_uid: evse, connector_id: conn, body: body })
}

fn sess_put(sid :: Str, body :: jv.Json) -> push.PushKind {
  SessionPut({ country_code: "NL", party_id: "TNM", session_id: sid, body: body })
}

fn sess_patch(sid :: Str, body :: jv.Json) -> push.PushKind {
  SessionPatch({ country_code: "NL", party_id: "TNM", session_id: sid, body: body })
}

fn cdr_post(body :: jv.Json) -> push.PushKind {
  CdrPost({ body: body })
}

fn tok_put(uid :: Str, body :: jv.Json) -> push.PushKind {
  TokenPut({ country_code: "DE", party_id: "ABC", token_uid: uid, body: body })
}

# ---- push_method -----------------------------------------------
fn test_method_location_put() -> Result[Unit, Str] {
  assert_eq_str("PUT", push.push_method(loc_put("L1")), "LocationPut")
}

fn test_method_location_patch() -> Result[Unit, Str] {
  assert_eq_str("PATCH", push.push_method(loc_patch("L1", JNull)), "LocationPatch")
}

fn test_method_evse_patch() -> Result[Unit, Str] {
  assert_eq_str("PATCH", push.push_method(evse_patch("L1", "E1", JNull)), "EvsePatch")
}

fn test_method_connector_patch() -> Result[Unit, Str] {
  assert_eq_str("PATCH", push.push_method(conn_patch("L1", "E1", "C1", JNull)), "ConnectorPatch")
}

fn test_method_session_put() -> Result[Unit, Str] {
  assert_eq_str("PUT", push.push_method(sess_put("S1", JNull)), "SessionPut")
}

fn test_method_session_patch() -> Result[Unit, Str] {
  assert_eq_str("PATCH", push.push_method(sess_patch("S1", JNull)), "SessionPatch")
}

fn test_method_cdr_post() -> Result[Unit, Str] {
  assert_eq_str("POST", push.push_method(cdr_post(JNull)), "CdrPost")
}

fn test_method_token_put() -> Result[Unit, Str] {
  assert_eq_str("PUT", push.push_method(tok_put("RFID-A", JNull)), "TokenPut")
}

# ---- push_url --------------------------------------------------
fn test_url_location_put() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1", push.push_url(base(), loc_put("L1")), "LocationPut URL")
}

fn test_url_location_patch() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L42", push.push_url(base(), loc_patch("L42", JNull)), "LocationPatch URL")
}

fn test_url_evse_patch() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1/EVSE-1", push.push_url(base(), evse_patch("L1", "EVSE-1", JNull)), "EvsePatch URL")
}

fn test_url_connector_patch() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1/EVSE-1/1", push.push_url(base(), conn_patch("L1", "EVSE-1", "1", JNull)), "ConnectorPatch URL")
}

fn test_url_session_put() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/sessions/NL/TNM/S-7", push.push_url(base(), sess_put("S-7", JNull)), "SessionPut URL")
}

fn test_url_session_patch() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.3.0/sessions/NL/TNM/S-7", push.push_url(b230(), sess_patch("S-7", JNull)), "SessionPatch URL")
}

fn test_url_cdr_post() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/cdrs", push.push_url(base(), cdr_post(JNull)), "CdrPost URL")
}

fn test_url_token_put() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/tokens/DE/ABC/RFID-A", push.push_url(base(), tok_put("RFID-A", JNull)), "TokenPut URL")
}

# ---- push_body (transparency) ----------------------------------
fn test_body_transparent_location_put() -> Result[Unit, Str] {
  let body := JObj([("id", JStr("L1"))])
  let got := push.push_body(LocationPut({ country_code: "NL", party_id: "TNM", location_id: "L1", body: body }))
  assert_eq_str(jv.stringify(body), jv.stringify(got), "body roundtrip")
}

fn test_body_transparent_cdr_post() -> Result[Unit, Str] {
  let body := JObj([("id", JStr("CDR-1")), ("total_cost", JInt(420))])
  let got := push.push_body(cdr_post(body))
  assert_eq_str(jv.stringify(body), jv.stringify(got), "CDR body roundtrip")
}

# ---- URL helpers (spot checks) ---------------------------------
fn test_location_url_helper() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1", push.location_url(base(), "NL", "TNM", "L1"), "location_url")
}

fn test_evse_url_helper() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1/EVSE-9", push.evse_url(base(), "NL", "TNM", "L1", "EVSE-9"), "evse_url")
}

fn test_connector_url_helper() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1/EVSE-9/2", push.connector_url(base(), "NL", "TNM", "L1", "EVSE-9", "2"), "connector_url")
}

fn test_session_url_helper() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.3.0/sessions/DE/ABC/S-7", push.session_url(b230(), "DE", "ABC", "S-7"), "session_url")
}

fn test_token_url_helper() -> Result[Unit, Str] {
  assert_eq_str("https://emsp.example/ocpi/2.2.1/tokens/DE/ABC/RFID-Z", push.token_url(base(), "DE", "ABC", "RFID-Z"), "token_url")
}

# ---- build_request -- structural assertions --------------------
#
# Build a request for each kind and assert: method, URL, body
# encoding, and that the OCPI headers (Authorization, from/to
# party tuple) are populated. We don't assert against a live
# socket — that's the conformance harness.
fn cpo_party() -> party.PartyId {
  party.new("NL", "EXM")
}

fn emsp_party() -> party.PartyId {
  party.new("DE", "ABC")
}

fn target() -> push.PushTarget {
  { party: emsp_party(), base_url: base(), token: "secret-token-b64" }
}

fn req_for(kind :: push.PushKind) -> HttpRequest {
  push.build_request(cpo_party(), target(), kind)
}

fn test_build_method_url_cdr() -> Result[Unit, Str] {
  let r := req_for(cdr_post(JObj([("id", JStr("CDR-1"))])))
  let m_ok := assert_eq_str("POST", r.method, "CDR method")
  let u_ok := assert_eq_str("https://emsp.example/ocpi/2.2.1/cdrs", r.url, "CDR url")
  and_ok(m_ok, u_ok)
}

fn test_build_method_url_evse() -> Result[Unit, Str] {
  let r := req_for(evse_patch("L1", "EVSE-1", JObj([("status", JStr("CHARGING"))])))
  let m_ok := assert_eq_str("PATCH", r.method, "evse method")
  let u_ok := assert_eq_str("https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1/EVSE-1", r.url, "evse url")
  and_ok(m_ok, u_ok)
}

fn test_build_has_authorization() -> Result[Unit, Str] {
  let r := req_for(loc_put("L1"))
  match map.get(r.headers, h.h_authorization()) {
    None => fail("Authorization header missing"),
    Some(v) => assert_eq_str("Token secret-token-b64", v, "Authorization value"),
  }
}

fn test_build_has_from_party() -> Result[Unit, Str] {
  let r := req_for(loc_put("L1"))
  let cc := map.get(r.headers, h.h_from_country_code())
  let pi := map.get(r.headers, h.h_from_party_id())
  match cc {
    None => fail("from-country-code missing"),
    Some(c) => match pi {
      None => fail("from-party-id missing"),
      Some(p) => {
        let c_ok := assert_eq_str("NL", c, "from-country-code")
        and_ok(c_ok, assert_eq_str("EXM", p, "from-party-id"))
      },
    },
  }
}

fn test_build_has_to_party() -> Result[Unit, Str] {
  let r := req_for(loc_put("L1"))
  let cc := map.get(r.headers, h.h_to_country_code())
  let pi := map.get(r.headers, h.h_to_party_id())
  match cc {
    None => fail("to-country-code missing"),
    Some(c) => match pi {
      None => fail("to-party-id missing"),
      Some(p) => {
        let c_ok := assert_eq_str("DE", c, "to-country-code")
        and_ok(c_ok, assert_eq_str("ABC", p, "to-party-id"))
      },
    },
  }
}

fn test_build_has_json_body() -> Result[Unit, Str] {
  let body := JObj([("id", JStr("L1")), ("name", JStr("Depot 1"))])
  let r := req_for(LocationPut({ country_code: "NL", party_id: "TNM", location_id: "L1", body: body }))
  let ct_ok := match map.get(r.headers, "content-type") {
    None => fail("content-type missing"),
    Some(v) => assert_eq_str("application/json", v, "content-type"),
  }
  let body_ok := match r.body {
    None => fail("request body missing"),
    Some(_) => pass(),
  }
  and_ok(ct_ok, body_ok)
}

fn and_ok(a :: Result[Unit, Str], b :: Result[Unit, Str]) -> Result[Unit, Str] {
  match a {
    Err(_) => a,
    Ok(_) => b,
  }
}

# ---- Suite + runner --------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [test_method_location_put(), test_method_location_patch(), test_method_evse_patch(), test_method_connector_patch(), test_method_session_put(), test_method_session_patch(), test_method_cdr_post(), test_method_token_put(), test_url_location_put(), test_url_location_patch(), test_url_evse_patch(), test_url_connector_patch(), test_url_session_put(), test_url_session_patch(), test_url_cdr_post(), test_url_token_put(), test_body_transparent_location_put(), test_body_transparent_cdr_post(), test_location_url_helper(), test_evse_url_helper(), test_connector_url_helper(), test_session_url_helper(), test_token_url_helper(), test_build_method_url_cdr(), test_build_method_url_evse(), test_build_has_authorization(), test_build_has_from_party(), test_build_has_to_party(), test_build_has_json_body()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

