# lex-ocpi — Conformance harness tests (issue #10)
#
# Two layers:
#
#   1. Direct tests of `src/conformance.lex` — every predicate
#      exercised with positive + negative cases.
#
#   2. End-to-end flow tests that dispatch a request through
#      `route.dispatch` and assert the response passes
#      `conformance.assert_envelope`. This is the "fake-CPO /
#      fake-eMSP" pattern in its minimal form: no HTTP, just the
#      in-process registry, with the conformance library acting
#      as the wire-shape contract that every handler must satisfy.
#
# The matching live-loop scenarios from #5 / #7 / #8 (a fake HTTP
# peer that 503s twice, a 3-eMSP fanout with one failure, the
# multi-thread idempotency race) need a mock transport that
# doesn't exist yet; they slot in on top of this library in a
# future PR.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str

import "lex-schema/json_value" as jv

import "../src/conformance" as conf
import "../src/envelope"    as env
import "../src/headers"     as h
import "../src/party"       as party
import "../src/route"       as route
import "../src/status"      as status

# ---- Test plumbing ----------------------------------------------

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

fn assert_ok(r :: Result[Unit, conf.ConformanceError], label :: Str) -> Result[Unit, Str] {
  match r {
    Ok(_)  => pass(),
    Err(e) => fail(str.concat(label, str.concat(": ", conf.render(e)))),
  }
}

fn assert_err(r :: Result[Unit, conf.ConformanceError], label :: Str) -> Result[Unit, Str] {
  match r {
    Ok(_)  => fail(str.concat(label, ": expected Err, got Ok")),
    Err(_) => pass(),
  }
}

# ---- classify --------------------------------------------------

fn test_classify_success() -> Result[Unit, Str] {
  match conf.classify(1000) { Success => pass(), _ => fail("1000 should be Success") }
}
fn test_classify_client() -> Result[Unit, Str] {
  match conf.classify(2003) { ClientError => pass(), _ => fail("2003 should be ClientError") }
}
fn test_classify_server() -> Result[Unit, Str] {
  match conf.classify(3001) { ServerError => pass(), _ => fail("3001 should be ServerError") }
}
fn test_classify_hub() -> Result[Unit, Str] {
  match conf.classify(4001) { HubError => pass(), _ => fail("4001 should be HubError") }
}
fn test_classify_unknown_low() -> Result[Unit, Str] {
  match conf.classify(500) { Unknown => pass(), _ => fail("500 should be Unknown") }
}
fn test_classify_unknown_high() -> Result[Unit, Str] {
  match conf.classify(5000) { Unknown => pass(), _ => fail("5000 should be Unknown") }
}

# ---- check_envelope --------------------------------------------

fn ok_envelope() -> env.OcpiResponse {
  { data: JNull, status_code: 1000, status_message: "",
    timestamp: "2026-05-16T00:00:00Z" }
}

fn err_envelope(code :: Int) -> env.OcpiResponse {
  { data: JNull, status_code: code, status_message: "Bad",
    timestamp: "2026-05-16T00:00:00Z" }
}

fn test_envelope_ok_success() -> Result[Unit, Str] {
  assert_ok(conf.check_envelope(ok_envelope()), "1000 envelope")
}

fn test_envelope_ok_client_error() -> Result[Unit, Str] {
  assert_ok(conf.check_envelope(err_envelope(2003)), "2003 envelope")
}

fn test_envelope_missing_timestamp() -> Result[Unit, Str] {
  let r := { data: JNull, status_code: 1000, status_message: "",
             timestamp: "" }
  assert_err(conf.check_envelope(r), "empty timestamp")
}

fn test_envelope_unknown_band() -> Result[Unit, Str] {
  let r := { data: JNull, status_code: 9999, status_message: "x",
             timestamp: "2026-05-16T00:00:00Z" }
  assert_err(conf.check_envelope(r), "9999 status_code")
}

fn test_envelope_message_missing_on_err() -> Result[Unit, Str] {
  let r := { data: JNull, status_code: 2003, status_message: "",
             timestamp: "2026-05-16T00:00:00Z" }
  assert_err(conf.check_envelope(r), "2003 with empty message")
}

fn test_envelope_message_empty_on_success_ok() -> Result[Unit, Str] {
  # Spec allows empty status_message on 1xxx success.
  assert_ok(conf.check_envelope(ok_envelope()), "empty msg on 1000 is OK")
}

# ---- check_envelope_all ---------------------------------------

fn test_envelope_all_collects_errors() -> Result[Unit, Str] {
  # 2003 (client error) with empty timestamp AND empty
  # status_message — should yield 2 errors (band is valid, so the
  # only failures are the missing fields).
  let r := { data: JNull, status_code: 2003, status_message: "",
             timestamp: "" }
  let errs := conf.check_envelope_all(r)
  assert_true(list.len(errs) == 2,
              str.concat("expected 2 errors, got ",
                int.to_str(list.len(errs))))
}

# ---- check_module_request_headers ----------------------------

fn good_headers() -> h.OcpiHeaders {
  h.new("Token abc", "rid-1", "corr-1",
        party.new("NL", "EXM"), party.new("DE", "ABC"))
}

fn test_module_headers_happy() -> Result[Unit, Str] {
  assert_ok(conf.check_module_request_headers(good_headers()),
            "well-formed module headers")
}

fn test_module_headers_missing_auth() -> Result[Unit, Str] {
  let hs := h.new("", "rid-1", "corr-1",
                  party.new("NL", "EXM"), party.new("DE", "ABC"))
  assert_err(conf.check_module_request_headers(hs), "missing authorization")
}

fn test_module_headers_wrong_auth_scheme() -> Result[Unit, Str] {
  let hs := h.new("Bearer xyz", "rid-1", "corr-1",
                  party.new("NL", "EXM"), party.new("DE", "ABC"))
  assert_err(conf.check_module_request_headers(hs), "Bearer rejected")
}

fn test_module_headers_missing_request_id() -> Result[Unit, Str] {
  let hs := h.new("Token x", "", "corr",
                  party.new("NL", "EXM"), party.new("DE", "ABC"))
  assert_err(conf.check_module_request_headers(hs), "missing request_id")
}

fn test_module_headers_missing_from_party() -> Result[Unit, Str] {
  let hs := h.new("Token x", "rid", "corr",
                  party.new("", ""), party.new("DE", "ABC"))
  assert_err(conf.check_module_request_headers(hs), "missing from-party")
}

fn test_module_headers_country_wrong_length() -> Result[Unit, Str] {
  let hs := h.new("Token x", "rid", "corr",
                  party.new("NLD", "EXM"), party.new("DE", "ABC"))
  assert_err(conf.check_module_request_headers(hs), "country_code length")
}

# ---- check_response_echoes_request ----------------------------

fn test_echo_happy() -> Result[Unit, Str] {
  let req := good_headers()
  let resp := map.set(map.set(map.new(),
                "x-request-id", "rid-1"),
                "x-correlation-id", "corr-1")
  assert_ok(conf.check_response_echoes_request(req, resp), "headers echoed")
}

fn test_echo_request_id_missing() -> Result[Unit, Str] {
  let req := good_headers()
  let resp := map.set(map.new(), "x-correlation-id", "corr-1")
  assert_err(conf.check_response_echoes_request(req, resp),
             "missing request_id in resp")
}

fn test_echo_request_id_mismatch() -> Result[Unit, Str] {
  let req := good_headers()
  let resp := map.set(map.set(map.new(),
                "x-request-id", "rid-DIFFERENT"),
                "x-correlation-id", "corr-1")
  assert_err(conf.check_response_echoes_request(req, resp),
             "request_id changed in resp")
}

# ---- check_pagination_headers ---------------------------------

fn test_pagination_happy() -> Result[Unit, Str] {
  let resp := map.set(map.set(map.new(),
                "x-total-count", "42"),
                "x-limit", "10")
  assert_ok(conf.check_pagination_headers(resp), "well-formed pagination")
}

fn test_pagination_total_missing() -> Result[Unit, Str] {
  let resp := map.set(map.new(), "x-limit", "10")
  assert_err(conf.check_pagination_headers(resp), "missing x-total-count")
}

fn test_pagination_limit_invalid() -> Result[Unit, Str] {
  let resp := map.set(map.set(map.new(),
                "x-total-count", "42"),
                "x-limit", "ten")
  assert_err(conf.check_pagination_headers(resp), "non-integer limit")
}

fn test_pagination_negative_count() -> Result[Unit, Str] {
  let resp := map.set(map.set(map.new(),
                "x-total-count", "-1"),
                "x-limit", "10")
  assert_err(conf.check_pagination_headers(resp), "negative count")
}

fn test_link_header_present() -> Result[Unit, Str] {
  let resp := map.set(map.new(), "link",
    "<https://example.com/locations?offset=10>; rel=\"next\"")
  assert_ok(conf.check_link_header_present(resp), "well-formed Link")
}

fn test_link_header_missing_rel() -> Result[Unit, Str] {
  let resp := map.set(map.new(), "link",
    "<https://example.com/locations?offset=10>; rel=\"prev\"")
  assert_err(conf.check_link_header_present(resp), "Link lacks rel=next")
}

# ---- check_authorization edge cases ---------------------------

fn test_auth_token_scheme() -> Result[Unit, Str] {
  # Direct check via good_headers wrapping.
  let hs := h.new("Token base64payload", "rid", "corr",
                  party.new("NL", "EXM"), party.new("DE", "ABC"))
  assert_ok(conf.check_module_request_headers(hs), "Token <b64> accepted")
}

# ---- End-to-end flow ------------------------------------------
#
# Wire a tiny route.Registry, dispatch a request, assert the
# response envelope passes conformance.

fn handler_returning_loc(_req :: route.OcpiRequest) -> route.HandlerResult {
  HOk(JObj([("id", JStr("LOC-1")), ("name", JStr("Depot 1"))]))
}

fn build_registry() -> route.Registry {
  route.handler(route.new(), "GET", "locations", handler_returning_loc)
}

fn mk_request(path :: Str) -> route.OcpiRequest {
  route.request(
    "GET", "locations", path,
    map.new(),
    map.new(),
    good_headers(),
    JNull)
}

fn test_flow_dispatch_envelope_conforms() -> Result[Unit, Str] {
  let resp := route.dispatch(build_registry(),
                              mk_request("/locations"),
                              "2026-05-16T00:00:00Z")
  match conf.check_envelope(resp) {
    Ok(_)  => pass(),
    Err(e) => fail(str.concat("dispatched response not spec-conforming: ",
                              conf.render(e))),
  }
}

fn test_flow_unknown_route_envelope_conforms() -> Result[Unit, Str] {
  # Hitting a registered method but unknown path → fallback fires;
  # the fallback's HErr is wrapped into a 2xxx envelope. Whatever
  # the fallback returns MUST still be a well-formed envelope.
  let resp := route.dispatch(route.new(),
                              mk_request("/locations"),
                              "2026-05-16T00:00:00Z")
  let env_ok := match conf.check_envelope(resp) {
    Ok(_)  => pass(),
    Err(e) => fail(str.concat("fallback envelope not conforming: ",
                              conf.render(e))),
  }
  # And it must be a client-error band (the request was malformed
  # from the peer's perspective — module didn't exist).
  let band_ok := match conf.classify(resp.status_code) {
    ClientError => pass(),
    _           => fail(str.concat("fallback should be 2xxx, got ",
                          int.to_str(resp.status_code))),
  }
  match env_ok { Err(_) => env_ok, Ok(_) => band_ok }
}

fn test_flow_assertion_helpers_work() -> Result[Unit, Str] {
  let resp := route.dispatch(build_registry(),
                              mk_request("/locations"),
                              "2026-05-16T00:00:00Z")
  # The `assert_envelope` variant is a one-liner test-friendly
  # form that renders the structured error to Str.
  conf.assert_envelope(resp)
}

# ---- Suite + runner ------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    # classify
    test_classify_success(),
    test_classify_client(),
    test_classify_server(),
    test_classify_hub(),
    test_classify_unknown_low(),
    test_classify_unknown_high(),
    # check_envelope
    test_envelope_ok_success(),
    test_envelope_ok_client_error(),
    test_envelope_missing_timestamp(),
    test_envelope_unknown_band(),
    test_envelope_message_missing_on_err(),
    test_envelope_message_empty_on_success_ok(),
    # check_envelope_all
    test_envelope_all_collects_errors(),
    # check_module_request_headers
    test_module_headers_happy(),
    test_module_headers_missing_auth(),
    test_module_headers_wrong_auth_scheme(),
    test_module_headers_missing_request_id(),
    test_module_headers_missing_from_party(),
    test_module_headers_country_wrong_length(),
    # check_response_echoes_request
    test_echo_happy(),
    test_echo_request_id_missing(),
    test_echo_request_id_mismatch(),
    # check_pagination_headers
    test_pagination_happy(),
    test_pagination_total_missing(),
    test_pagination_limit_invalid(),
    test_pagination_negative_count(),
    test_link_header_present(),
    test_link_header_missing_rel(),
    # check_authorization
    test_auth_token_scheme(),
    # End-to-end flow
    test_flow_dispatch_envelope_conforms(),
    test_flow_unknown_route_envelope_conforms(),
    test_flow_assertion_helpers_work(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r { Ok(_) => n, Err(_) => n + 1 }
    })
}
