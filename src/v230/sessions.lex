# lex-ocpi — OCPI 2.3.0 Sessions module
#
# 2.3.0 Session shape mirrors 2.2.1 with the new enum widenings
# (auth method, session status, CdrDimensionType including the V2X
# import/export pair) already captured in `enums.lex`.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- CdrToken ---------------------------------------------------

fn cdr_token_schema() -> s.ModelSchema {
  {
    title: "CdrToken",
    description: "OCPI 2.3.0 — CdrToken",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("uid",          [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("type",         [StrOneOf(en.all_token_type())]),
      s.required_str("contract_id",  [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

fn cdr_dimension_schema() -> s.ModelSchema {
  {
    title: "CdrDimension",
    description: "OCPI 2.3.0 — CdrDimension",
    fields: [
      s.required_str("type",   [StrOneOf(en.all_cdr_dimension_type())]),
      s.required_float("volume", []),
    ],
  }
}

fn charging_period_schema() -> s.ModelSchema {
  {
    title: "ChargingPeriod",
    description: "OCPI 2.3.0 — ChargingPeriod",
    fields: [
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_array("dimensions",    KObject(cdr_dimension_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("tariff_id", [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

fn price_schema() -> s.ModelSchema {
  {
    title: "Price",
    description: "OCPI 2.3.0 — Price",
    fields: [
      s.required_float("excl_vat", []),
      s.optional(s.required_float("incl_vat", [])),
    ],
  }
}

fn session_schema() -> s.ModelSchema {
  {
    title: "Session",
    description: "OCPI 2.3.0 — Session object",
    fields: [
      s.required_str("country_code",       [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",           [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",                 [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("start_date_time",    [StrNonEmpty]),
      s.optional(s.required_str("end_date_time", [StrNonEmpty])),
      s.required_float("kwh",              []),
      s.required_object("cdr_token",       cdr_token_schema()),
      s.required_str("auth_method",        [StrOneOf(en.all_auth_method())]),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
      s.required_str("location_id",        [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("evse_uid",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("connector_id",       [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("meter_id",[StrMaxLen(255)])),
      s.required_str("currency",           [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("charging_periods",
        KObject(charging_period_schema()), [])),
      s.optional(s.required_object("total_cost", price_schema())),
      s.required_str("status",             [StrOneOf(en.all_session_status())]),
      s.required_str("last_updated",       [StrNonEmpty]),
    ],
  }
}

fn validate_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(session_schema(), j)
}
