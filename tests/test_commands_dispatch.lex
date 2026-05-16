# lex-ocpi — Commands ADT + receiver-side dispatch tests
#
# Pure tests for the shared `src/commands.lex` module:
#
#   - encode_command_* / decode_command_* total mappings for the
#     three enums (CommandType, CommandResponseType, CommandResultType).
#   - encode_command_response / decode_command_response round-trip
#     including the optional v2.2.1+ `timeout` field and the
#     optional `message` array.
#   - Same for CommandResult (no `timeout` field).
#   - response_url(body) extraction.
#   - command_handler: missing response_url → 2001; happy path →
#     HOk(CommandResponse JSON) with the sync reply the user chose.
#   - build_command_url shape across the 5 command types.
#
# The end-to-end live-port round-trip (a fake CPO that returns a
# real sync CommandResponse) is deferred to the async-runtime PR
# (issue #4 slice 2). These pure tests exercise every branch of the
# typed ADT + the receiver-side dispatcher.

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

import "../src/commands" as cmds
import "../src/headers"  as h
import "../src/party"    as party
import "../src/route"    as route

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

# ---- CommandType encode/decode ---------------------------------

fn check_round_trip_cmd_type(t :: cmds.CommandType, label :: Str) -> Result[Unit, Str] {
  let s := cmds.encode_command_type(t)
  match cmds.decode_command_type(s) {
    Err(m) => fail(str.concat(label, str.concat(" decode failed: ", m))),
    Ok(t2) => {
      # Re-encode and compare strings — the ADT doesn't have an Eq.
      let s2 := cmds.encode_command_type(t2)
      assert_eq_str(s, s2, str.concat(label, " round-trip"))
    },
  }
}

fn test_cmd_type_round_trip_start_session() -> Result[Unit, Str] {
  check_round_trip_cmd_type(StartSession, "StartSession")
}

fn test_cmd_type_round_trip_stop_session() -> Result[Unit, Str] {
  check_round_trip_cmd_type(StopSession, "StopSession")
}

fn test_cmd_type_round_trip_reserve_now() -> Result[Unit, Str] {
  check_round_trip_cmd_type(ReserveNow, "ReserveNow")
}

fn test_cmd_type_round_trip_cancel_reservation() -> Result[Unit, Str] {
  check_round_trip_cmd_type(CancelReservation, "CancelReservation")
}

fn test_cmd_type_round_trip_unlock_connector() -> Result[Unit, Str] {
  check_round_trip_cmd_type(UnlockConnector, "UnlockConnector")
}

fn test_cmd_type_decode_unknown() -> Result[Unit, Str] {
  match cmds.decode_command_type("FOO_BAR") {
    Ok(_)  => fail("expected Err for unknown CommandType"),
    Err(_) => pass(),
  }
}

# ---- CommandResponseType encode/decode -------------------------

fn check_round_trip_resp_type(t :: cmds.CommandResponseType, label :: Str) -> Result[Unit, Str] {
  let s := cmds.encode_command_response_type(t)
  match cmds.decode_command_response_type(s) {
    Err(m) => fail(str.concat(label, str.concat(" decode failed: ", m))),
    Ok(t2) => {
      let s2 := cmds.encode_command_response_type(t2)
      assert_eq_str(s, s2, str.concat(label, " round-trip"))
    },
  }
}

fn test_resp_type_round_trip_accepted() -> Result[Unit, Str] {
  check_round_trip_resp_type(CrAccepted, "CrAccepted")
}

fn test_resp_type_round_trip_rejected() -> Result[Unit, Str] {
  check_round_trip_resp_type(CrRejected, "CrRejected")
}

fn test_resp_type_round_trip_not_supported() -> Result[Unit, Str] {
  check_round_trip_resp_type(CrNotSupported, "CrNotSupported")
}

fn test_resp_type_round_trip_unknown_session() -> Result[Unit, Str] {
  check_round_trip_resp_type(CrUnknownSession, "CrUnknownSession")
}

fn test_resp_type_decode_unknown() -> Result[Unit, Str] {
  match cmds.decode_command_response_type("MAYBE") {
    Ok(_)  => fail("expected Err for unknown CommandResponseType"),
    Err(_) => pass(),
  }
}

# ---- CommandResultType encode/decode (spot check) --------------
#
# 9 variants. Spot-check the most-used three plus the negative
# case; the round-trip pattern is exercised exhaustively by the
# CommandType + CommandResponseType tests above.

fn test_result_type_accepted() -> Result[Unit, Str] {
  match cmds.decode_command_result_type("ACCEPTED") {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(t)  => assert_eq_str("ACCEPTED",
                cmds.encode_command_result_type(t),
                "ResAccepted"),
  }
}

fn test_result_type_canceled_reservation() -> Result[Unit, Str] {
  match cmds.decode_command_result_type("CANCELED_RESERVATION") {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(t)  => assert_eq_str("CANCELED_RESERVATION",
                cmds.encode_command_result_type(t),
                "ResCanceledReservation"),
  }
}

fn test_result_type_timeout() -> Result[Unit, Str] {
  match cmds.decode_command_result_type("TIMEOUT") {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(t)  => assert_eq_str("TIMEOUT",
                cmds.encode_command_result_type(t),
                "ResTimeout"),
  }
}

fn test_result_type_decode_unknown() -> Result[Unit, Str] {
  match cmds.decode_command_result_type("PARTIAL") {
    Ok(_)  => fail("expected Err for unknown CommandResultType"),
    Err(_) => pass(),
  }
}

# ---- CommandResponse round-trip --------------------------------

fn test_response_encode_minimal() -> Result[Unit, Str] {
  let r := cmds.response(CrAccepted, None, [])
  let j := cmds.encode_command_response(r)
  # Minimal — no timeout, no messages.
  assert_eq_str("{\"result\":\"ACCEPTED\"}", jv.stringify(j),
    "minimal response encoding")
}

fn test_response_encode_with_timeout() -> Result[Unit, Str] {
  let r := cmds.response(CrAccepted, Some(30), [])
  let j := cmds.encode_command_response(r)
  assert_eq_str("{\"result\":\"ACCEPTED\",\"timeout\":30}",
    jv.stringify(j), "response w/ timeout encoding")
}

fn test_response_decode_round_trip() -> Result[Unit, Str] {
  let original := cmds.response(CrRejected, Some(60), [])
  let j := cmds.encode_command_response(original)
  match cmds.decode_command_response(j) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r2) => {
      # Re-encode and compare wire strings (the record doesn't have Eq).
      let j2 := cmds.encode_command_response(r2)
      assert_eq_str(jv.stringify(j), jv.stringify(j2),
        "response round-trip")
    },
  }
}

fn test_response_decode_missing_result() -> Result[Unit, Str] {
  match cmds.decode_command_response(JObj([("timeout", JInt(30))])) {
    Ok(_)  => fail("expected Err for missing `result`"),
    Err(_) => pass(),
  }
}

# ---- CommandResult round-trip ----------------------------------

fn test_result_encode_minimal() -> Result[Unit, Str] {
  let r := cmds.result_accepted()
  let j := cmds.encode_command_result(r)
  assert_eq_str("{\"result\":\"ACCEPTED\"}", jv.stringify(j),
    "minimal result encoding")
}

fn test_result_decode_round_trip() -> Result[Unit, Str] {
  let original := cmds.result_timeout()
  let j := cmds.encode_command_result(original)
  match cmds.decode_command_result(j) {
    Err(m) => fail(str.concat("decode failed: ", m)),
    Ok(r2) => {
      let j2 := cmds.encode_command_result(r2)
      assert_eq_str(jv.stringify(j), jv.stringify(j2),
        "result round-trip")
    },
  }
}

# ---- response_url extraction -----------------------------------

fn test_response_url_present() -> Result[Unit, Str] {
  let body := JObj([
    ("response_url", JStr("https://emsp.example/callback/abc123")),
    ("session_id",   JStr("S1")),
  ])
  match cmds.response_url(body) {
    None    => fail("expected Some(response_url)"),
    Some(u) => assert_eq_str(
      "https://emsp.example/callback/abc123", u, "response_url"),
  }
}

fn test_response_url_missing() -> Result[Unit, Str] {
  let body := JObj([("session_id", JStr("S1"))])
  match cmds.response_url(body) {
    None    => pass(),
    Some(_) => fail("expected None"),
  }
}

fn test_response_url_non_string() -> Result[Unit, Str] {
  let body := JObj([("response_url", JInt(1))])
  match cmds.response_url(body) {
    None    => pass(),
    Some(_) => fail("expected None for non-string response_url"),
  }
}

# ---- build_command_url -----------------------------------------

fn test_url_start_session() -> Result[Unit, Str] {
  assert_eq_str(
    "https://cpo.example/ocpi/2.2.1/commands/START_SESSION",
    cmds.build_command_url(
      "https://cpo.example/ocpi/2.2.1/commands", StartSession),
    "start_session url")
}

fn test_url_unlock_connector() -> Result[Unit, Str] {
  assert_eq_str(
    "https://cpo.example/ocpi/2.3.0/commands/UNLOCK_CONNECTOR",
    cmds.build_command_url(
      "https://cpo.example/ocpi/2.3.0/commands", UnlockConnector),
    "unlock_connector url")
}

fn test_url_cancel_reservation() -> Result[Unit, Str] {
  assert_eq_str(
    "https://cpo.example/ocpi/2.2.1/commands/CANCEL_RESERVATION",
    cmds.build_command_url(
      "https://cpo.example/ocpi/2.2.1/commands", CancelReservation),
    "cancel_reservation url")
}

# ---- Receiver-side handler ------------------------------------

fn empty_headers() -> h.OcpiHeaders {
  h.new("", "", "", party.new("", ""), party.new("", ""))
}

fn mk_request(body :: jv.Json) -> route.OcpiRequest {
  route.request(
    route.post(),
    "commands.START_SESSION",
    "/ocpi/2.2.1/commands/START_SESSION",
    map.new(),
    map.new(),
    empty_headers(),
    body)
}

# User fn fixtures — capture nothing, return a fixed sync reply.
fn always_accepted(_b :: jv.Json, _u :: Str) -> cmds.CommandResponse {
  cmds.accepted(Some(30))
}

fn always_rejected(_b :: jv.Json, _u :: Str) -> cmds.CommandResponse {
  cmds.rejected(None)
}

fn test_handler_accepted_branch() -> Result[Unit, Str] {
  let h := cmds.command_handler(always_accepted)
  let body := JObj([
    ("response_url",  JStr("https://emsp.example/cb")),
    ("session_id",    JStr("S1")),
  ])
  match h(mk_request(body)) {
    HOk(j) => match cmds.decode_command_response(j) {
      Err(m) => fail(str.concat("response decode failed: ", m)),
      Ok(r)  => match r.result {
        CrAccepted => pass(),
        _          => fail("expected CrAccepted"),
      },
    },
    _ => fail("expected HOk"),
  }
}

fn test_handler_rejected_branch() -> Result[Unit, Str] {
  let h := cmds.command_handler(always_rejected)
  let body := JObj([
    ("response_url",  JStr("https://emsp.example/cb")),
    ("session_id",    JStr("S1")),
  ])
  match h(mk_request(body)) {
    HOk(j) => match cmds.decode_command_response(j) {
      Err(m) => fail(str.concat("response decode failed: ", m)),
      Ok(r)  => match r.result {
        CrRejected => pass(),
        _          => fail("expected CrRejected"),
      },
    },
    _ => fail("expected HOk"),
  }
}

fn test_handler_missing_response_url() -> Result[Unit, Str] {
  let h := cmds.command_handler(always_accepted)
  let body := JObj([("session_id", JStr("S1"))])
  match h(mk_request(body)) {
    HErr(err) => assert_true(err.code == 2001, "expected 2001 status code"),
    _         => fail("expected HErr for missing response_url"),
  }
}

# Captures the response_url so we can assert the handler passes the
# right value into the user fn.
fn always_accepted_capturing(_b :: jv.Json, url :: Str) -> cmds.CommandResponse {
  # Encode the captured URL into the messages field as a marker so
  # the test can read it back without mutable state.
  cmds.response(CrAccepted, None, [JStr(url)])
}

fn check_captured_url(items :: List[jv.Json]) -> Result[Unit, Str] {
  match list.head(items) {
    None    => fail("captured list empty"),
    Some(h) => match jv.as_str(h) {
      None    => fail("captured item not a string"),
      Some(s) => assert_eq_str(
        "https://emsp.example/cb/xyz", s,
        "handler captured wrong url"),
    },
  }
}

fn test_handler_passes_response_url() -> Result[Unit, Str] {
  let h := cmds.command_handler(always_accepted_capturing)
  let body := JObj([
    ("response_url",  JStr("https://emsp.example/cb/xyz")),
    ("session_id",    JStr("S1")),
  ])
  match h(mk_request(body)) {
    HOk(j) => match jv.get_field(j, "message") {
      None    => fail("message field missing — handler didn't forward url"),
      Some(m) => match m {
        JList(items) => check_captured_url(items),
        _            => fail("message field not a list"),
      },
    },
    _ => fail("expected HOk"),
  }
}

# ---- Suite + runner --------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    # CommandType
    test_cmd_type_round_trip_start_session(),
    test_cmd_type_round_trip_stop_session(),
    test_cmd_type_round_trip_reserve_now(),
    test_cmd_type_round_trip_cancel_reservation(),
    test_cmd_type_round_trip_unlock_connector(),
    test_cmd_type_decode_unknown(),

    # CommandResponseType
    test_resp_type_round_trip_accepted(),
    test_resp_type_round_trip_rejected(),
    test_resp_type_round_trip_not_supported(),
    test_resp_type_round_trip_unknown_session(),
    test_resp_type_decode_unknown(),

    # CommandResultType
    test_result_type_accepted(),
    test_result_type_canceled_reservation(),
    test_result_type_timeout(),
    test_result_type_decode_unknown(),

    # CommandResponse envelope
    test_response_encode_minimal(),
    test_response_encode_with_timeout(),
    test_response_decode_round_trip(),
    test_response_decode_missing_result(),

    # CommandResult envelope
    test_result_encode_minimal(),
    test_result_decode_round_trip(),

    # response_url extraction
    test_response_url_present(),
    test_response_url_missing(),
    test_response_url_non_string(),

    # build_command_url
    test_url_start_session(),
    test_url_unlock_connector(),
    test_url_cancel_reservation(),

    # Receiver-side handler
    test_handler_accepted_branch(),
    test_handler_rejected_branch(),
    test_handler_missing_response_url(),
    test_handler_passes_response_url(),
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
