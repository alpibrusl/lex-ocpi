# lex-ocpi — OCPI 2.3.0 Commands module
#
# Wire shape unchanged from 2.2.1.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"  as en
import "./tokens" as tokens

# ---- DisplayText (shared) ---------------------------------------

fn display_text_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.3.0 — DisplayText",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

# ---- CommandResponse / CommandResult ----------------------------

fn command_response_schema() -> s.ModelSchema {
  {
    title: "CommandResponse",
    description: "OCPI 2.3.0 — Synchronous CommandResponse",
    fields: [
      s.required_str("result",  [StrOneOf(en.all_command_response_type())]),
      s.required_int("timeout", [IntNonNegative]),
      s.optional(s.required_array("message",
        KObject(display_text_schema()), [])),
    ],
  }
}

fn validate_command_response(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(command_response_schema(), j)
}

fn command_result_schema() -> s.ModelSchema {
  {
    title: "CommandResult",
    description: "OCPI 2.3.0 — Asynchronous CommandResult",
    fields: [
      s.required_str("result", [StrNonEmpty]),
      s.optional(s.required_array("message",
        KObject(display_text_schema()), [])),
    ],
  }
}

fn validate_command_result(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(command_result_schema(), j)
}

# ---- StartSession -----------------------------------------------

fn start_session_schema() -> s.ModelSchema {
  {
    title: "StartSession",
    description: "OCPI 2.3.0 — StartSession command body",
    fields: [
      s.required_str("response_url",        [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",            tokens.token_schema()),
      s.required_str("location_id",         [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid", [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn validate_start_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(start_session_schema(), j)
}

# ---- StopSession ------------------------------------------------

fn stop_session_schema() -> s.ModelSchema {
  {
    title: "StopSession",
    description: "OCPI 2.3.0 — StopSession command body",
    fields: [
      s.required_str("response_url", [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("session_id",   [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn validate_stop_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(stop_session_schema(), j)
}

# ---- ReserveNow -------------------------------------------------

fn reserve_now_schema() -> s.ModelSchema {
  {
    title: "ReserveNow",
    description: "OCPI 2.3.0 — ReserveNow command body",
    fields: [
      s.required_str("response_url",        [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",            tokens.token_schema()),
      s.required_str("expiry_date",         [StrNonEmpty]),
      s.required_str("reservation_id",      [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("location_id",         [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid", [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn validate_reserve_now(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(reserve_now_schema(), j)
}

# ---- CancelReservation / UnlockConnector ------------------------

fn cancel_reservation_schema() -> s.ModelSchema {
  {
    title: "CancelReservation",
    description: "OCPI 2.3.0 — CancelReservation command body",
    fields: [
      s.required_str("response_url",   [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("reservation_id", [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn validate_cancel_reservation(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(cancel_reservation_schema(), j)
}

fn unlock_connector_schema() -> s.ModelSchema {
  {
    title: "UnlockConnector",
    description: "OCPI 2.3.0 — UnlockConnector command body",
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
