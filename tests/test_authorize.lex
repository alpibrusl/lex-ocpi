# lex-ocpi — real-time token authorization tests
#
# Pure tests for the shared `AuthorizationResult` ADT and the
# per-version authorize modules:
#
#   - auth.decode maps each AllowedType string to the matching
#     variant; negative cases (missing field, wrong type, unknown
#     string) surface as Err.
#   - auth.encode is the identity on the wrapped JSON, so
#     decode . encode round-trips for every variant.
#   - URL + body builders shape the wire request correctly per version
#     (v2.1.1 has no country/party in the path; v2.2.1 / v2.3.0 do).
#   - body_validator accepts null + empty `{}` + valid LocationReferences,
#     rejects malformed payloads.
#   - authorize_handler extracts token_uid from path_params, plumbs the
#     body through body_to_refs, invokes the user fn, and wraps the
#     resulting AuthorizationResult back into HOk with the same JSON.
#
# The end-to-end live-port round-trip (spawn fake eMSP, real
# authorize_token call over [net]) is deferred to an example program —
# these pure tests already exercise every branch of the decoder + handler.

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

import "../src/authorize" as auth
import "../src/headers"   as h
import "../src/party"     as party
import "../src/route"     as route

import "../src/v211/authorize" as auth211
import "../src/v221/authorize" as auth221
import "../src/v230/authorize" as auth230

# ---- Test plumbing ----------------------------------------------

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

# ---- Fixtures ----------------------------------------------------

# Minimal AuthorizationInfo — v2.2.1 / v2.3.0 require a `token` field
# alongside `allowed`. We don't validate against the full schema here
# (that's tests/test_v221_schemas.lex's job); the decoder only looks
# at `allowed`, so a minimal payload is enough.

fn info_with_allowed(allowed :: Str) -> jv.Json {
  JObj([("allowed", JStr(allowed))])
}

# ---- Decoder happy paths (all 5 variants) -----------------------

fn check_allowed(r :: auth.AuthorizationResult) -> Result[Unit, Str] {
  match r {
    Allowed(_) => pass(),
    _          => fail("expected Allowed variant"),
  }
}

fn check_blocked(r :: auth.AuthorizationResult) -> Result[Unit, Str] {
  match r {
    Blocked(_) => pass(),
    _          => fail("expected Blocked variant"),
  }
}

fn check_expired(r :: auth.AuthorizationResult) -> Result[Unit, Str] {
  match r {
    Expired(_) => pass(),
    _          => fail("expected Expired variant"),
  }
}

fn check_no_credit(r :: auth.AuthorizationResult) -> Result[Unit, Str] {
  match r {
    NoCredit(_) => pass(),
    _           => fail("expected NoCredit variant"),
  }
}

fn check_not_allowed(r :: auth.AuthorizationResult) -> Result[Unit, Str] {
  match r {
    NotAllowed(_) => pass(),
    _             => fail("expected NotAllowed variant"),
  }
}

fn test_decode_allowed() -> Result[Unit, Str] {
  match auth.decode(info_with_allowed(auth.allowed_str())) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r)  => check_allowed(r),
  }
}

fn test_decode_blocked() -> Result[Unit, Str] {
  match auth.decode(info_with_allowed(auth.blocked_str())) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r)  => check_blocked(r),
  }
}

fn test_decode_expired() -> Result[Unit, Str] {
  match auth.decode(info_with_allowed(auth.expired_str())) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r)  => check_expired(r),
  }
}

fn test_decode_no_credit() -> Result[Unit, Str] {
  match auth.decode(info_with_allowed(auth.no_credit_str())) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r)  => check_no_credit(r),
  }
}

fn test_decode_not_allowed() -> Result[Unit, Str] {
  match auth.decode(info_with_allowed(auth.not_allowed_str())) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r)  => check_not_allowed(r),
  }
}

# ---- Decoder negative paths -------------------------------------

fn test_decode_missing_allowed() -> Result[Unit, Str] {
  match auth.decode(JObj([])) {
    Ok(_)  => fail("expected Err for empty object"),
    Err(_) => pass(),
  }
}

fn test_decode_non_string_allowed() -> Result[Unit, Str] {
  let j := JObj([("allowed", JInt(1))])
  match auth.decode(j) {
    Ok(_)  => fail("expected Err for non-string `allowed`"),
    Err(_) => pass(),
  }
}

fn test_decode_unknown_allowed() -> Result[Unit, Str] {
  let j := info_with_allowed("MAYBE")
  match auth.decode(j) {
    Ok(_)  => fail("expected Err for unknown `allowed` value"),
    Err(_) => pass(),
  }
}

# ---- Decode → encode round-trip ---------------------------------
#
# encode extracts the embedded JSON; decoding it again must land on
# the same variant. Spot-check Allowed + NotAllowed (boundary cases
# of the if-else chain).

fn test_round_trip_allowed() -> Result[Unit, Str] {
  let original := info_with_allowed(auth.allowed_str())
  match auth.decode(original) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r1) => match auth.decode(auth.encode(r1)) {
      Err(m) => fail(str.concat("re-decode failed: ", m)),
      Ok(r2) => check_allowed(r2),
    },
  }
}

fn test_round_trip_not_allowed() -> Result[Unit, Str] {
  let original := info_with_allowed(auth.not_allowed_str())
  match auth.decode(original) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r1) => match auth.decode(auth.encode(r1)) {
      Err(m) => fail(str.concat("re-decode failed: ", m)),
      Ok(r2) => check_not_allowed(r2),
    },
  }
}

# ---- URL builders (per version) ---------------------------------

fn test_url_v221() -> Result[Unit, Str] {
  assert_eq_str(
    "https://emsp.example/ocpi/2.2.1/tokens/NL/TNM/RFID-A/authorize",
    auth221.build_authorize_url(
      "https://emsp.example/ocpi/2.2.1/tokens", "NL", "TNM", "RFID-A"),
    "v2.2.1 url")
}

fn test_url_v211() -> Result[Unit, Str] {
  assert_eq_str(
    "https://emsp.example/ocpi/2.1.1/tokens/RFID-A/authorize",
    auth211.build_authorize_url(
      "https://emsp.example/ocpi/2.1.1/tokens", "RFID-A"),
    "v2.1.1 url")
}

fn test_url_v230() -> Result[Unit, Str] {
  assert_eq_str(
    "https://emsp.example/ocpi/2.3.0/tokens/DE/BMW/RFID-Z/authorize",
    auth230.build_authorize_url(
      "https://emsp.example/ocpi/2.3.0/tokens", "DE", "BMW", "RFID-Z"),
    "v2.3.0 url")
}

# ---- Body builders ----------------------------------------------

fn test_body_none_is_empty_object() -> Result[Unit, Str] {
  assert_eq_str("{}", auth221.build_authorize_body(None), "None body")
}

fn test_body_some_stringifies() -> Result[Unit, Str] {
  let refs := JObj([
    ("location_id", JStr("LOC1")),
  ])
  let got := auth221.build_authorize_body(Some(refs))
  # jv.stringify is canonical; for this shape it produces
  # {"location_id":"LOC1"} with no whitespace.
  assert_eq_str("{\"location_id\":\"LOC1\"}", got, "Some body")
}

# ---- Receiver-side handler --------------------------------------
#
# Build a fake user-supplied authorize fn, run authorize_handler's
# returned Handler against a synthetic OcpiRequest, and assert the
# resulting HandlerResult is HOk-wrapping the AuthorizationInfo with
# the expected `allowed` value.

fn empty_headers() -> h.OcpiHeaders {
  h.new("", "", "", party.new("", ""), party.new("", ""))
}

fn mk_request(token_uid :: Str, body :: jv.Json) -> route.OcpiRequest {
  route.request(
    route.post(),
    "tokens",
    "/ocpi/2.2.1/tokens/NL/TNM/RFID-A/authorize",
    map.set(map.new(), "token_uid", token_uid),
    map.new(),
    empty_headers(),
    body)
}

# Always-Allowed authorisation function — exercises the happy path.
fn auth_always_allowed(
  _uid  :: Str,
  _refs :: Option[jv.Json]
) -> auth.AuthorizationResult {
  Allowed(JObj([("allowed", JStr("ALLOWED"))]))
}

fn auth_always_blocked(
  _uid  :: Str,
  _refs :: Option[jv.Json]
) -> auth.AuthorizationResult {
  Blocked(JObj([("allowed", JStr("BLOCKED"))]))
}

fn check_handler_allowed(hr :: route.HandlerResult, want :: Str, label :: Str) -> Result[Unit, Str] {
  match hr {
    HOk(j) => match jv.get_field(j, "allowed") {
      None    => fail(str.concat(label, ": HOk payload missing `allowed`")),
      Some(v) => match jv.as_str(v) {
        None    => fail(str.concat(label, ": `allowed` not a string")),
        Some(s) => assert_eq_str(want, s, label),
      },
    },
    HOkList(_) => fail(str.concat(label, ": expected HOk, got HOkList")),
    HOkEmpty   => fail(str.concat(label, ": expected HOk, got HOkEmpty")),
    HErr(_)    => fail(str.concat(label, ": expected HOk, got HErr")),
  }
}

fn test_handler_allowed_branch() -> Result[Unit, Str] {
  let h := auth221.authorize_handler(auth_always_allowed)
  check_handler_allowed(h(mk_request("RFID-A", JNull)), "ALLOWED", "allowed-branch")
}

fn test_handler_blocked_branch() -> Result[Unit, Str] {
  let h := auth221.authorize_handler(auth_always_blocked)
  check_handler_allowed(h(mk_request("RFID-A", JNull)), "BLOCKED", "blocked-branch")
}

fn test_handler_missing_token_uid() -> Result[Unit, Str] {
  let h := auth221.authorize_handler(auth_always_allowed)
  # Request with empty path_params — the handler should surface a
  # 2001 OCPI error rather than crash or invent a token.
  let req := route.request(
    route.post(), "tokens", "/x",
    map.new(),
    map.new(),
    empty_headers(),
    JNull)
  match h(req) {
    HErr(err) => assert_true(err.code == 2001, "expected 2001 status code"),
    HOk(_)    => fail("expected HErr, got HOk"),
    HOkList(_)=> fail("expected HErr, got HOkList"),
    HOkEmpty  => fail("expected HErr, got HOkEmpty"),
  }
}

# Round-trip: receiver handler builds the AuthorizationInfo, then
# the same JSON is fed back through the decoder — must land on the
# same variant. This is the wire-shape contract: encode . request
# . decode is the identity.

fn test_round_trip_handler_to_decoder() -> Result[Unit, Str] {
  let h := auth221.authorize_handler(auth_always_blocked)
  match h(mk_request("RFID-A", JNull)) {
    HOk(j)  => match auth.decode(j) {
      Err(m) => fail(str.concat("re-decode failed: ", m)),
      Ok(r)  => check_blocked(r),
    },
    _ => fail("expected HOk"),
  }
}

# ---- body_validator ---------------------------------------------

fn test_body_validator_accepts_null() -> Result[Unit, Str] {
  match auth221.body_validator(JNull) {
    Ok(_)  => pass(),
    Err(_) => fail("null body should validate"),
  }
}

fn test_body_validator_accepts_empty_object() -> Result[Unit, Str] {
  match auth221.body_validator(JObj([])) {
    Ok(_)  => pass(),
    Err(_) => fail("empty object should validate"),
  }
}

fn test_body_validator_accepts_valid_refs() -> Result[Unit, Str] {
  let j := JObj([("location_id", JStr("LOC1"))])
  match auth221.body_validator(j) {
    Ok(_)  => pass(),
    Err(_) => fail("valid LocationReferences should validate"),
  }
}

fn test_body_validator_rejects_missing_location_id() -> Result[Unit, Str] {
  let j := JObj([("evse_uids", JList([JStr("EVSE1")]))])
  match auth221.body_validator(j) {
    Ok(_)  => fail("body without location_id should fail validation"),
    Err(_) => pass(),
  }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    # decoder happy paths (all 5 variants)
    test_decode_allowed(),
    test_decode_blocked(),
    test_decode_expired(),
    test_decode_no_credit(),
    test_decode_not_allowed(),

    # decoder negative paths
    test_decode_missing_allowed(),
    test_decode_non_string_allowed(),
    test_decode_unknown_allowed(),

    # decode → encode round-trip
    test_round_trip_allowed(),
    test_round_trip_not_allowed(),

    # URL builders (v211 + v221 + v230)
    test_url_v221(),
    test_url_v211(),
    test_url_v230(),

    # body builders
    test_body_none_is_empty_object(),
    test_body_some_stringifies(),

    # receiver-side handler
    test_handler_allowed_branch(),
    test_handler_blocked_branch(),
    test_handler_missing_token_uid(),
    test_round_trip_handler_to_decoder(),

    # body validator
    test_body_validator_accepts_null(),
    test_body_validator_accepts_empty_object(),
    test_body_validator_accepts_valid_refs(),
    test_body_validator_rejects_missing_location_id(),
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
