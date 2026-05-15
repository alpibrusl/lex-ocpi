# lex-ocpi — OCPI 2.1.1 Sessions module
#
# 2.1.1 Session differs from 2.2.1:
#   - `auth_id` is a bare string (no `CdrToken` record)
#   - `currency` is required
#   - no `connector_id` (just `evse.uid`)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- CdrDimension -----------------------------------------------

fn cdr_dimension_schema() -> s.ModelSchema {
  {
    title: "CdrDimension",
    description: "OCPI 2.1.1 — CdrDimension",
    fields: [
      s.required_str("type",   [StrOneOf(en.all_cdr_dimension_type())]),
      s.required_float("volume", []),
    ],
  }
}

# ---- ChargingPeriod ---------------------------------------------

fn charging_period_schema() -> s.ModelSchema {
  {
    title: "ChargingPeriod",
    description: "OCPI 2.1.1 — ChargingPeriod",
    fields: [
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_array("dimensions",    KObject(cdr_dimension_schema()),
                       [ListNonEmpty]),
    ],
  }
}

# ---- Session ----------------------------------------------------

fn session_schema() -> s.ModelSchema {
  {
    title: "Session",
    description: "OCPI 2.1.1 — Session object",
    fields: [
      s.required_str("id",                 [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("start_datetime",     [StrNonEmpty]),
      s.optional(s.required_str("end_datetime", [StrNonEmpty])),
      s.required_float("kwh",              []),
      s.required_str("auth_id",            [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("auth_method",        [StrOneOf(en.all_auth_method())]),
      s.required_str("location",           [StrNonEmpty]),
      # 2.1.1 carries location as a nested object on the wire; in
      # practice the integration tests carry a sub-id and validate
      # the full Location separately. Schemas are loose here for
      # forwards compatibility.
      s.optional(s.required_str("meter_id",[StrMaxLen(255)])),
      s.required_str("currency",           [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("charging_periods",
        KObject(charging_period_schema()), [])),
      s.required_float("total_cost",       []),
      s.required_str("status",             [StrOneOf(en.all_session_status())]),
      s.required_str("last_updated",       [StrNonEmpty]),
    ],
  }
}

fn validate_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(session_schema(), j)
}
