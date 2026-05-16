# lex-ocpi — Commands ADTs + JSON ↔ ADT mapping (version-agnostic)
#
# The OCPI Commands module flows in two stages:
#
#   1. Sync. eMSP `POST /commands/{TYPE}` to CPO with a `response_url`.
#      CPO replies with `CommandResponse(result :: CommandResponseType)`:
#      one of ACCEPTED / REJECTED / NOT_SUPPORTED / UNKNOWN_SESSION.
#   2. Async. CPO acts on the command (signals the charger), then later
#      `POST {response_url}` with `CommandResult(result :: CommandResultType)`:
#      one of ACCEPTED / CANCELED_RESERVATION / EVSE_OCCUPIED /
#      EVSE_INOPERATIVE / FAILED / NOT_SUPPORTED / REJECTED / TIMEOUT /
#      UNKNOWN_RESERVATION.
#
# This module ships the version-agnostic typed ADTs + the JSON ↔ ADT
# mappers. The per-version `v{211,221,230}/commands.lex` modules carry
# the body schemas (StartSession / StopSession / ReserveNow /
# CancelReservation / UnlockConnector — `CancelReservation` is
# 2.2.1+) and the per-version handler / sender glue.
#
# v0.1 of this surface is the **sync half** — the typed ADT + the
# receiver-side handler that returns the sync CommandResponse. The
# **async half** (in-flight map, polling-with-timeout
# wait_for_result, callback-POST helper) is tracked at
# [#4 (slice 2)](https://github.com/alpibrusl/lex-ocpi/issues/4).
#
# Spec references:
#   OCPI 2.2.1 — Part III §13 (Commands module)
#   OCPI 2.3.0 — Part III §13
#
# Effects: none. (Per-version modules add `[net]` for `submit_command`.)

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "./client" as client
import "./route"  as route
import "./error"  as oe

# ---- CommandType (the five POST routes a CPO exposes) -----------

type CommandType =
    StartSession
  | StopSession
  | ReserveNow
  | CancelReservation       # 2.2.1+ only — v2.1.1 routes reject it as NOT_SUPPORTED
  | UnlockConnector

# Wire-string constants. Mirror the per-version `enums.lex`
# (`en.cmd_start_session()` etc.); kept here as a single source of
# truth so callers don't have to import a version-specific enums.

fn cmd_start_session_str()      -> Str { "START_SESSION" }
fn cmd_stop_session_str()       -> Str { "STOP_SESSION" }
fn cmd_reserve_now_str()        -> Str { "RESERVE_NOW" }
fn cmd_cancel_reservation_str() -> Str { "CANCEL_RESERVATION" }
fn cmd_unlock_connector_str()   -> Str { "UNLOCK_CONNECTOR" }

fn encode_command_type(t :: CommandType) -> Str {
  match t {
    StartSession      => cmd_start_session_str(),
    StopSession       => cmd_stop_session_str(),
    ReserveNow        => cmd_reserve_now_str(),
    CancelReservation => cmd_cancel_reservation_str(),
    UnlockConnector   => cmd_unlock_connector_str(),
  }
}

fn decode_command_type(s :: Str) -> Result[CommandType, Str] {
  if s == cmd_start_session_str()        { Ok(StartSession) }
  else { if s == cmd_stop_session_str()       { Ok(StopSession) }
  else { if s == cmd_reserve_now_str()        { Ok(ReserveNow) }
  else { if s == cmd_cancel_reservation_str() { Ok(CancelReservation) }
  else { if s == cmd_unlock_connector_str()   { Ok(UnlockConnector) }
  else { Err(str.concat("CommandType not in catalogue: ", s)) }
  } } } }
}

# ---- CommandResponseType (sync reply to a command POST) ---------

type CommandResponseType =
    CrAccepted
  | CrRejected
  | CrNotSupported
  | CrUnknownSession

fn cmdr_accepted_str()        -> Str { "ACCEPTED" }
fn cmdr_rejected_str()        -> Str { "REJECTED" }
fn cmdr_not_supported_str()   -> Str { "NOT_SUPPORTED" }
fn cmdr_unknown_session_str() -> Str { "UNKNOWN_SESSION" }

fn encode_command_response_type(t :: CommandResponseType) -> Str {
  match t {
    CrAccepted        => cmdr_accepted_str(),
    CrRejected        => cmdr_rejected_str(),
    CrNotSupported    => cmdr_not_supported_str(),
    CrUnknownSession  => cmdr_unknown_session_str(),
  }
}

fn decode_command_response_type(s :: Str) -> Result[CommandResponseType, Str] {
  if s == cmdr_accepted_str()        { Ok(CrAccepted) }
  else { if s == cmdr_rejected_str()       { Ok(CrRejected) }
  else { if s == cmdr_not_supported_str()  { Ok(CrNotSupported) }
  else { if s == cmdr_unknown_session_str(){ Ok(CrUnknownSession) }
  else { Err(str.concat("CommandResponseType not in catalogue: ", s)) }
  } } }
}

# ---- CommandResultType (async POST from CPO to response_url) ----

type CommandResultType =
    ResAccepted
  | ResCanceledReservation
  | ResEvseOccupied
  | ResEvseInoperative
  | ResFailed
  | ResNotSupported
  | ResRejected
  | ResTimeout
  | ResUnknownReservation

fn res_accepted_str()              -> Str { "ACCEPTED" }
fn res_canceled_reservation_str()  -> Str { "CANCELED_RESERVATION" }
fn res_evse_occupied_str()         -> Str { "EVSE_OCCUPIED" }
fn res_evse_inoperative_str()      -> Str { "EVSE_INOPERATIVE" }
fn res_failed_str()                -> Str { "FAILED" }
fn res_not_supported_str()         -> Str { "NOT_SUPPORTED" }
fn res_rejected_str()              -> Str { "REJECTED" }
fn res_timeout_str()               -> Str { "TIMEOUT" }
fn res_unknown_reservation_str()   -> Str { "UNKNOWN_RESERVATION" }

fn encode_command_result_type(t :: CommandResultType) -> Str {
  match t {
    ResAccepted             => res_accepted_str(),
    ResCanceledReservation  => res_canceled_reservation_str(),
    ResEvseOccupied         => res_evse_occupied_str(),
    ResEvseInoperative      => res_evse_inoperative_str(),
    ResFailed               => res_failed_str(),
    ResNotSupported         => res_not_supported_str(),
    ResRejected             => res_rejected_str(),
    ResTimeout              => res_timeout_str(),
    ResUnknownReservation   => res_unknown_reservation_str(),
  }
}

fn decode_command_result_type(s :: Str) -> Result[CommandResultType, Str] {
  if s == res_accepted_str()              { Ok(ResAccepted) }
  else { if s == res_canceled_reservation_str() { Ok(ResCanceledReservation) }
  else { if s == res_evse_occupied_str()        { Ok(ResEvseOccupied) }
  else { if s == res_evse_inoperative_str()     { Ok(ResEvseInoperative) }
  else { if s == res_failed_str()               { Ok(ResFailed) }
  else { if s == res_not_supported_str()        { Ok(ResNotSupported) }
  else { if s == res_rejected_str()             { Ok(ResRejected) }
  else { if s == res_timeout_str()              { Ok(ResTimeout) }
  else { if s == res_unknown_reservation_str()  { Ok(ResUnknownReservation) }
  else { Err(str.concat("CommandResultType not in catalogue: ", s)) }
  } } } } } } } }
}

# ---- CommandResponse envelope (sync) ----------------------------
#
# OCPI 2.1.1 ships only `{ result }`; OCPI 2.2.1 + 2.3.0 add the
# `timeout` integer (how many seconds the eMSP should wait before
# considering the async result timed out) and an optional
# `message :: List[DisplayText]`. The typed `CommandResponse`
# carries both — `timeout` is `Option[Int]` so v2.1.1 callers leave
# it None and the encoder omits it.

type CommandResponse = {
  result   :: CommandResponseType,
  timeout  :: Option[Int],
  messages :: List[jv.Json],         # validated DisplayText objects
}

fn response(
  res      :: CommandResponseType,
  timeout  :: Option[Int],
  messages :: List[jv.Json]
) -> CommandResponse {
  { result: res, timeout: timeout, messages: messages }
}

# Convenience constructors. The default timeout (60s) matches the
# OCPI spec's recommendation for ReserveNow/UnlockConnector; callers
# that know the underlying charger should override.

fn accepted(timeout :: Option[Int]) -> CommandResponse
  examples {
    accepted(Some(30)) =>
      { result: CrAccepted, timeout: Some(30), messages: [] },
  }
{
  response(CrAccepted, timeout, [])
}

fn rejected(timeout :: Option[Int]) -> CommandResponse {
  response(CrRejected, timeout, [])
}

fn not_supported() -> CommandResponse {
  response(CrNotSupported, None, [])
}

fn unknown_session() -> CommandResponse {
  response(CrUnknownSession, None, [])
}

# JSON encoding. The `timeout` field is omitted entirely when `None`
# (v2.1.1 path); `message` is omitted when the list is empty.

fn encode_command_response(r :: CommandResponse) -> jv.Json {
  let with_result := [("result", JStr(encode_command_response_type(r.result)))]
  let with_timeout := match r.timeout {
    None    => with_result,
    Some(t) => list.concat(with_result, [("timeout", JInt(t))]),
  }
  let final := if list.is_empty(r.messages) {
    with_timeout
  } else {
    list.concat(with_timeout, [("message", JList(r.messages))])
  }
  JObj(final)
}

# Decode a CommandResponse JSON (post-validation) into the typed
# record. Returns Err on missing / unrecognised `result`.

fn decode_command_response(j :: jv.Json) -> Result[CommandResponse, Str] {
  match jv.get_field(j, "result") {
    None     => Err("CommandResponse missing `result`"),
    Some(rv) => match jv.as_str(rv) {
      None    => Err("CommandResponse `result` is not a string"),
      Some(s) => match decode_command_response_type(s) {
        Err(why) => Err(why),
        Ok(t)    => Ok(response(t, decode_optional_timeout(j),
                                   decode_messages(j))),
      },
    },
  }
}

fn decode_optional_timeout(j :: jv.Json) -> Option[Int] {
  match jv.get_field(j, "timeout") {
    None     => None,
    Some(tv) => jv.as_int(tv),
  }
}

fn decode_messages(j :: jv.Json) -> List[jv.Json] {
  match jv.get_field(j, "message") {
    None     => [],
    Some(mv) => match mv {
      JList(items) => items,
      _            => [],
    },
  }
}

# ---- CommandResult envelope (async) -----------------------------
#
# Posted by the CPO to the eMSP's `response_url` once the underlying
# action completes (or times out). Shape: `{ result, optional
# message }` — no `timeout` field on the async side.

type CommandResult = {
  result   :: CommandResultType,
  messages :: List[jv.Json],
}

fn make_result(rt :: CommandResultType, messages :: List[jv.Json]) -> CommandResult {
  { result: rt, messages: messages }
}

fn result_accepted() -> CommandResult           { make_result(ResAccepted, []) }
fn result_failed() -> CommandResult             { make_result(ResFailed, []) }
fn result_rejected() -> CommandResult           { make_result(ResRejected, []) }
fn result_timeout() -> CommandResult            { make_result(ResTimeout, []) }
fn result_evse_occupied() -> CommandResult      { make_result(ResEvseOccupied, []) }
fn result_evse_inoperative() -> CommandResult   { make_result(ResEvseInoperative, []) }

fn encode_command_result(r :: CommandResult) -> jv.Json {
  let with_result := [("result", JStr(encode_command_result_type(r.result)))]
  let final := if list.is_empty(r.messages) {
    with_result
  } else {
    list.concat(with_result, [("message", JList(r.messages))])
  }
  JObj(final)
}

fn decode_command_result(j :: jv.Json) -> Result[CommandResult, Str] {
  match jv.get_field(j, "result") {
    None     => Err("CommandResult missing `result`"),
    Some(rv) => match jv.as_str(rv) {
      None    => Err("CommandResult `result` is not a string"),
      Some(s) => match decode_command_result_type(s) {
        Err(why) => Err(why),
        Ok(t)    => Ok(make_result(t, decode_messages(j))),
      },
    },
  }
}

# ---- Helper: extract response_url from a command body -----------
#
# Every command body has a top-level `response_url` field. The
# receiver-side handler grabs it before dispatching the user's
# response so the async-callback layer (issue #4 slice 2) knows
# where to POST the CommandResult later.

fn response_url(body :: jv.Json) -> Option[Str] {
  match jv.get_field(body, "response_url") {
    None    => None,
    Some(v) => jv.as_str(v),
  }
}

# ---- Receiver-side glue -----------------------------------------
#
# Lift a pure `(body, response_url) -> CommandResponse` into a
# `route.Handler`. The user's `handle` fn picks the sync reply (and
# in the async-runtime PR will also kick off the work that
# eventually POSTs the CommandResult to `response_url`).
#
# Body validation belongs at the route layer:
#   route.handler_with_schema(reg, route.post(), module_id,
#     v221_commands.validate_start_session,
#     commands.command_handler(my_start_session))
#
# The handler is identical across all 3 versions and all 5 command
# types. The route module string + the validator at the route layer
# are what disambiguate which command this is. The user fn typically
# starts with a quick discriminator on the body shape (`session_id`
# present => StopSession, `reservation_id` present => ReserveNow /
# CancelReservation, etc.) when one fn covers multiple endpoints —
# but the common case is one user fn per command type wired to its
# own route.

fn command_handler(
  handle :: (jv.Json, Str) -> CommandResponse
) -> (route.OcpiRequest) -> route.HandlerResult {
  fn (req :: route.OcpiRequest) -> route.HandlerResult {
    match response_url(req.body) {
      None      => route.fail(oe.invalid_parameters(
                     "command body missing `response_url`")),
      Some(url) => {
        let sync_reply := handle(req.body, url)
        route.ok(encode_command_response(sync_reply))
      },
    }
  }
}

# ---- Sender-side `[net]` helper ---------------------------------
#
# Build the per-command URL (`<base>/{TYPE}`), POST the body via
# `client.post_json`, decode the sync `CommandResponse`. The eMSP's
# `response_url` must be set inside `body` by the caller — this
# helper doesn't synthesise it because it depends on where the
# eMSP's own callback server is reachable from the CPO.
#
# The URL shape `{commands_base}/{TYPE}` is identical across 2.1.1
# / 2.2.1 / 2.3.0, so one sender helper covers all three.

fn submit_command(
  commands_base :: Str,
  cmd_type      :: CommandType,
  body          :: jv.Json,
  token_b64     :: Str
) -> [net] Result[CommandResponse, client.ClientError] {
  let url := build_command_url(commands_base, cmd_type)
  match client.post_json(url, jv.stringify(body), token_b64) {
    Err(err) => Err(err),
    Ok(j)    => match decode_command_response(j) {
      Err(why) => Err(BadEnvelope(why)),
      Ok(resp) => Ok(resp),
    },
  }
}

fn build_command_url(base :: Str, cmd_type :: CommandType) -> Str
  examples {
    build_command_url("https://cpo.example/ocpi/2.2.1/commands",
                      StartSession) =>
      "https://cpo.example/ocpi/2.2.1/commands/START_SESSION",
  }
{
  let with_slash := str.concat(base, "/")
  str.concat(with_slash, encode_command_type(cmd_type))
}
