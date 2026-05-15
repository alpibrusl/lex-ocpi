# lex-ocpi — OCPI 2.2.1 Commands module
#
# The Commands module lets an eMSP send remote actions to a CPO:
# `START_SESSION`, `STOP_SESSION`, `RESERVE_NOW`, `CANCEL_RESERVATION`,
# `UNLOCK_CONNECTOR`. The CPO returns a synchronous
# `CommandResponse` (ACCEPTED / REJECTED / NOT_SUPPORTED /
# UNKNOWN_SESSION), then later an asynchronous `CommandResult`
# at the eMSP's `response_url`.
#
# Spec references:
#   OCPI 2.2.1 — Part III §13 (Commands module)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"  as en
import "./tokens" as tokens

# ---- DisplayText (shared with other modules) ---------------------

fn display_text_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.2.1 — DisplayText",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

# ---- CommandResponse (sync response to a command POST) -----------

fn command_response_schema() -> s.ModelSchema {
  {
    title: "CommandResponse",
    description: "OCPI 2.2.1 — Synchronous CommandResponse",
    fields: [
      s.required_str("result",       [StrOneOf(en.all_command_response_type())]),
      s.required_int("timeout",      [IntNonNegative]),
      s.optional(s.required_array("message",
        KObject(display_text_schema()), [])),
    ],
  }
}

fn validate_command_response(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(command_response_schema(), j)
}

# ---- CommandResult (async — posted by CPO to eMSP's response_url) -

fn command_result_schema() -> s.ModelSchema {
  {
    title: "CommandResult",
    description: "OCPI 2.2.1 — Asynchronous CommandResult",
    fields: [
      s.required_str("result",       [StrOneOf(en.all_command_result_type())]),
      s.optional(s.required_array("message",
        KObject(display_text_schema()), [])),
    ],
  }
}

fn validate_command_result(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(command_result_schema(), j)
}

# ---- StartSession request body -----------------------------------

fn start_session_schema() -> s.ModelSchema {
  {
    title: "StartSession",
    description: "OCPI 2.2.1 — StartSession command body",
    fields: [
      s.required_str("response_url",            [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",                tokens.token_schema()),
      s.required_str("location_id",             [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid",     [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn validate_start_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(start_session_schema(), j)
}

# ---- StopSession request body ------------------------------------

fn stop_session_schema() -> s.ModelSchema {
  {
    title: "StopSession",
    description: "OCPI 2.2.1 — StopSession command body",
    fields: [
      s.required_str("response_url", [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("session_id",   [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn validate_stop_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(stop_session_schema(), j)
}

# ---- ReserveNow request body -------------------------------------

fn reserve_now_schema() -> s.ModelSchema {
  {
    title: "ReserveNow",
    description: "OCPI 2.2.1 — ReserveNow command body",
    fields: [
      s.required_str("response_url",         [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",             tokens.token_schema()),
      s.required_str("expiry_date",          [StrNonEmpty]),
      s.required_str("reservation_id",       [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("location_id",          [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid",  [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn validate_reserve_now(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(reserve_now_schema(), j)
}

# ---- CancelReservation request body ------------------------------

fn cancel_reservation_schema() -> s.ModelSchema {
  {
    title: "CancelReservation",
    description: "OCPI 2.2.1 — CancelReservation command body",
    fields: [
      s.required_str("response_url",   [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("reservation_id", [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn validate_cancel_reservation(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(cancel_reservation_schema(), j)
}

# ---- UnlockConnector request body --------------------------------

fn unlock_connector_schema() -> s.ModelSchema {
  {
    title: "UnlockConnector",
    description: "OCPI 2.2.1 — UnlockConnector command body",
    fields: [
      s.required_str("response_url", [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("location_id",  [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("evse_uid",     [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("connector_id", [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn validate_unlock_connector(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(unlock_connector_schema(), j)
}
