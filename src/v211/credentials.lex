# lex-ocpi — OCPI 2.1.1 Credentials module
#
# 2.1.1 Credentials has a FLAT shape — no `roles[]` array. A single
# party identifies itself directly via top-level `country_code` /
# `party_id` / `business_details` fields. This is the main breaking
# change between 2.1.1 and 2.2.x: 2.2 introduced multi-role peers,
# 2.1.1 assumes one role per Credentials exchange.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "../v211/locations" as locs

# ---- Credentials (v2.1.1 — flat) --------------------------------

fn credentials_schema_v211() -> s.ModelSchema {
  {
    title: "Credentials",
    description: "OCPI 2.1.1 — Credentials object (flat, no roles array)",
    fields: [
      s.required_str("url",          [StrNonEmpty, StrMaxLen(255)]),
      s.required_str("token",        [StrNonEmpty, StrMaxLen(64)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_object("business_details", locs.business_details_schema()),
    ],
  }
}

fn validate_credentials_v211(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(credentials_schema_v211(), j)
}
