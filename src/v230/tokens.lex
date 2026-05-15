# lex-ocpi — OCPI 2.3.0 Tokens module
#
# Same wire shape as 2.2.1 Tokens; the enum widening for `type`,
# `whitelist`, and `allowed_type` is captured in `enums.lex`.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- EnergyContract ---------------------------------------------

fn energy_contract_schema() -> s.ModelSchema {
  {
    title: "EnergyContract",
    description: "OCPI 2.3.0 — EnergyContract",
    fields: [
      s.required_str("supplier_name", [StrNonEmpty, StrMaxLen(64)]),
      s.optional(s.required_str("contract_id", [StrNonEmpty, StrMaxLen(64)])),
    ],
  }
}

# ---- Token ------------------------------------------------------

fn token_schema() -> s.ModelSchema {
  {
    title: "Token",
    description: "OCPI 2.3.0 — Token object",
    fields: [
      s.required_str("country_code",    [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",        [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("uid",             [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("type",            [StrOneOf(en.all_token_type())]),
      s.required_str("contract_id",     [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("visual_number", [StrMaxLen(64)])),
      s.required_str("issuer",          [StrNonEmpty, StrMaxLen(64)]),
      s.optional(s.required_str("group_id",     [StrMaxLen(36)])),
      s.required_bool("valid"),
      s.required_str("whitelist",       [StrOneOf(en.all_whitelist_type())]),
      s.optional(s.required_str("language",        [StrMaxLen(2)])),
      s.optional(s.required_str("default_profile_type", [StrNonEmpty])),
      s.optional(s.required_object("energy_contract",
        energy_contract_schema())),
      s.required_str("last_updated",    [StrNonEmpty]),
    ],
  }
}

fn validate_token(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(token_schema(), j)
}

# ---- LocationReferences -----------------------------------------

fn location_references_schema() -> s.ModelSchema {
  {
    title: "LocationReferences",
    description: "OCPI 2.3.0 — LocationReferences",
    fields: [
      s.required_str("location_id", [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_array("evse_uids",
        KStr([StrNonEmpty, StrMaxLen(36)]), [])),
    ],
  }
}

fn validate_location_references(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(location_references_schema(), j)
}

# ---- AuthorizationInfo ------------------------------------------

fn authorization_info_schema() -> s.ModelSchema {
  {
    title: "AuthorizationInfo",
    description: "OCPI 2.3.0 — AuthorizationInfo",
    fields: [
      s.required_str("allowed",        [StrOneOf(en.all_allowed_type())]),
      s.required_object("token",       token_schema()),
      s.optional(s.required_object("location",
        location_references_schema())),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_object("info", info_display_schema())),
    ],
  }
}

fn info_display_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.3.0 — Info DisplayText",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

fn validate_authorization_info(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(authorization_info_schema(), j)
}
