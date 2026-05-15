# lex-ocpi — OCPI 2.1.1 CDRs module
#
# 2.1.1 CDR differs from 2.2.1:
#   - uses `auth_id` (bare string) not `cdr_token` (record)
#   - location is the *full* Location object inline, not a CdrLocation
#     summary (heavier on the wire, simpler for the schema)
#   - no `cdr_location` / SignedData split — just the body fields
#   - `total_cost` is a float, not a Price record
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"    as en
import "./sessions" as sess
import "./tariffs"  as tariffs
import "./locations" as locs

# ---- Cdr --------------------------------------------------------

fn cdr_schema() -> s.ModelSchema {
  {
    title: "CDR",
    description: "OCPI 2.1.1 — Charge Detail Record",
    fields: [
      s.required_str("id",             [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_str("stop_date_time",  [StrNonEmpty]),
      s.required_str("auth_id",        [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("auth_method",    [StrOneOf(en.all_auth_method())]),
      s.required_object("location",    locs.location_schema()),
      s.optional(s.required_str("meter_id", [StrMaxLen(255)])),
      s.required_str("currency",       [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("tariffs",
        KObject(tariffs.tariff_schema()), [])),
      s.required_array("charging_periods",
        KObject(sess.charging_period_schema()), [ListNonEmpty]),
      s.required_float("total_cost",   []),
      s.required_float("total_energy", []),
      s.required_float("total_time",   []),
      s.optional(s.required_float("total_parking_time", [])),
      s.optional(s.required_str("remark", [StrMaxLen(255)])),
      s.required_str("last_updated",   [StrNonEmpty]),
    ],
  }
}

fn validate_cdr(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(cdr_schema(), j)
}
