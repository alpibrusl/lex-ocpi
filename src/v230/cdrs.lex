# lex-ocpi — OCPI 2.3.0 CDRs module
#
# Wire shape matches 2.2.1; the only material delta is that
# `CdrDimensionType` now legally includes the V2X import/export
# pair (already captured in `enums.lex`).
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"    as en
import "./sessions" as sess

# ---- SignedValue / SignedData -----------------------------------

fn signed_value_schema() -> s.ModelSchema {
  {
    title: "SignedValue",
    description: "OCPI 2.3.0 — SignedValue",
    fields: [
      s.required_str("nature",       [StrNonEmpty, StrMaxLen(32)]),
      s.required_str("plain_data",   [StrNonEmpty, StrMaxLen(512)]),
      s.required_str("signed_data",  [StrNonEmpty, StrMaxLen(5000)]),
    ],
  }
}

fn signed_data_schema() -> s.ModelSchema {
  {
    title: "SignedData",
    description: "OCPI 2.3.0 — SignedData wrapper",
    fields: [
      s.required_str("encoding_method", [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_int("encoding_method_version", [IntNonNegative])),
      s.optional(s.required_str("public_key", [StrMaxLen(512)])),
      s.required_array("signed_values", KObject(signed_value_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("url", [StrMaxLen(512)])),
    ],
  }
}

# ---- CdrLocation ------------------------------------------------

fn cdr_geo_schema() -> s.ModelSchema {
  {
    title: "GeoLocation",
    description: "OCPI 2.3.0 — coordinates",
    fields: [
      s.required_str("latitude",  [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("longitude", [StrNonEmpty, StrMaxLen(11)]),
    ],
  }
}

fn cdr_location_schema() -> s.ModelSchema {
  {
    title: "CdrLocation",
    description: "OCPI 2.3.0 — Snapshot of the location for a CDR",
    fields: [
      s.required_str("id",             [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("name", [StrMaxLen(255)])),
      s.required_str("address",        [StrNonEmpty, StrMaxLen(45)]),
      s.required_str("city",           [StrNonEmpty, StrMaxLen(45)]),
      s.optional(s.required_str("postal_code", [StrMaxLen(10)])),
      s.optional(s.required_str("state",       [StrMaxLen(20)])),
      s.required_str("country",        [StrNonEmpty, StrMaxLen(3)]),
      s.required_object("coordinates", cdr_geo_schema()),
      s.required_str("evse_uid",       [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("evse_id",        [StrNonEmpty, StrMaxLen(48)]),
      s.required_str("connector_id",   [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("connector_standard",
        [StrOneOf(en.all_connector_type())]),
      s.required_str("connector_format",
        [StrOneOf(en.all_connector_format())]),
      s.required_str("connector_power_type",
        [StrOneOf(en.all_power_type())]),
    ],
  }
}

# ---- Stub tariff reference --------------------------------------

fn stub_tariff_ref_schema() -> s.ModelSchema {
  {
    title: "Tariff",
    description: "OCPI 2.3.0 — Tariff reference embedded in a CDR",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("currency",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

# ---- Cdr --------------------------------------------------------

fn cdr_schema() -> s.ModelSchema {
  {
    title: "CDR",
    description: "OCPI 2.3.0 — Charge Detail Record",
    fields: [
      s.required_str("country_code",  [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",      [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",            [StrNonEmpty, StrMaxLen(39)]),
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_str("end_date_time",   [StrNonEmpty]),
      s.optional(s.required_str("session_id", [StrNonEmpty, StrMaxLen(36)])),
      s.required_object("cdr_token",    sess.cdr_token_schema()),
      s.required_str("auth_method",     [StrOneOf(en.all_auth_method())]),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
      s.required_object("cdr_location", cdr_location_schema()),
      s.optional(s.required_str("meter_id", [StrMaxLen(255)])),
      s.required_str("currency",        [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("tariffs",
        KObject(stub_tariff_ref_schema()), [])),
      s.required_array("charging_periods",
        KObject(sess.charging_period_schema()), [ListNonEmpty]),
      s.optional(s.required_object("signed_data", signed_data_schema())),
      s.required_object("total_cost",   sess.price_schema()),
      s.required_float("total_energy",  []),
      s.required_float("total_time",    []),
      s.optional(s.required_float("total_parking_time",  [])),
      s.optional(s.required_str("remark", [StrMaxLen(255)])),
      s.optional(s.required_bool("credit")),
      s.optional(s.required_str("credit_reference_id", [StrMaxLen(39)])),
      s.required_str("last_updated",    [StrNonEmpty]),
    ],
  }
}

fn validate_cdr(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(cdr_schema(), j)
}
