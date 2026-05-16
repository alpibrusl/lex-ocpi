# lex-ocpi — OCPI 2.1.1 Tokens module
#
# 2.1.1 Token differs from 2.2.1:
#   - no `country_code` / `party_id` on the object itself
#   - no `default_profile_type`, `energy_contract`
#   - simpler shape overall
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- Token ------------------------------------------------------

fn token_schema() -> s.ModelSchema {
  {
    title: "Token",
    description: "OCPI 2.1.1 — Token object",
    fields: [
      s.required_str("uid",          [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("type",         [StrOneOf(en.all_token_type())]),
      s.required_str("auth_id",      [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("visual_number", [StrMaxLen(64)])),
      s.required_str("issuer",       [StrNonEmpty, StrMaxLen(64)]),
      s.required_bool("valid"),
      s.required_str("whitelist",    [StrOneOf(en.all_whitelist_type())]),
      s.optional(s.required_str("language", [StrMaxLen(2)])),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_token(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(token_schema(), j)
}

# ---- LocationReferences (Authorize request body) ----------------

fn location_references_schema() -> s.ModelSchema {
  {
    title: "LocationReferences",
    description: "OCPI 2.1.1 — LocationReferences",
    fields: [
      s.required_str("location_id", [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_array("evse_uids",
        KStr([StrNonEmpty, StrMaxLen(36)]), [])),
      s.optional(s.required_array("connector_ids",
        KStr([StrNonEmpty, StrMaxLen(36)]), [])),
    ],
  }
}

fn validate_location_references(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(location_references_schema(), j)
}

# ---- AuthorizationInfo (Authorize response) ---------------------

fn authorization_info_schema() -> s.ModelSchema {
  {
    title: "AuthorizationInfo",
    description: "OCPI 2.1.1 — AuthorizationInfo",
    fields: [
      s.required_str("allowed",  [StrOneOf(en.all_allowed_type())]),
      s.optional(s.required_object("location",
        location_references_schema())),
      s.optional(s.required_object("info", info_schema())),
    ],
  }
}

fn info_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.1.1 — DisplayText for AuthorizationInfo",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

fn validate_authorization_info(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(authorization_info_schema(), j)
}
