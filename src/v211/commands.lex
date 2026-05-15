# lex-ocpi — OCPI 2.1.1 Commands module
#
# 2.1.1 Commands differs from 2.2.1:
#   - no CANCEL_RESERVATION (added in 2.2)
#   - StartSession carries `token` as a full Token record + bare
#     `evse_uid` / `connector_id`
#   - ReserveNow has no `authorization_reference`
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"  as en
import "./tokens" as tokens

# ---- CommandResponse --------------------------------------------

fn command_response_schema() -> s.ModelSchema {
  {
    title: "CommandResponse",
    description: "OCPI 2.1.1 — Synchronous CommandResponse",
    fields: [
      s.required_str("result", [StrOneOf(en.all_command_response_type())]),
    ],
  }
}

fn validate_command_response(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(command_response_schema(), j)
}

# ---- StartSession request body ----------------------------------

fn start_session_schema() -> s.ModelSchema {
  {
    title: "StartSession",
    description: "OCPI 2.1.1 — StartSession command body",
    fields: [
      s.required_str("response_url",        [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",            tokens.token_schema()),
      s.required_str("location_id",         [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid", [StrNonEmpty, StrMaxLen(36)])),
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
    description: "OCPI 2.1.1 — StopSession command body",
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
    description: "OCPI 2.1.1 — ReserveNow command body",
    fields: [
      s.required_str("response_url",        [StrNonEmpty, StrMaxLen(255)]),
      s.required_object("token",            tokens.token_schema()),
      s.required_str("expiry_date",         [StrNonEmpty]),
      s.required_str("reservation_id",      [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("location_id",         [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_uid", [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn validate_reserve_now(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(reserve_now_schema(), j)
}

# ---- UnlockConnector --------------------------------------------

fn unlock_connector_schema() -> s.ModelSchema {
  {
    title: "UnlockConnector",
    description: "OCPI 2.1.1 — UnlockConnector command body",
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
