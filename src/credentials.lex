# lex-ocpi — Credentials module
#
# The Credentials module is the per-pair handshake every OCPI peer
# walks through right after version discovery. A pair of peers
# exchanges `Credentials` objects to swap long-lived tokens
# (`token_C` in spec terms); subsequent module traffic is
# authorised by the issued token.
#
# Wire shape (every version of OCPI):
#
#   Credentials {
#     token:    "<token-C — used by the receiver to call the sender>",
#     url:      "<sender's versions endpoint>",
#     roles:    [ CredentialsRole { ... }, ... ],   # OCPI 2.2+
#   }
#
# OCPI 2.1.1 has a flatter shape (`country_code`, `party_id`,
# `business_details` directly on `Credentials`); 2.2+ groups those
# fields into a list of `CredentialsRole` entries so a single peer
# can register as multiple roles (e.g. CPO + EMSP).
#
# Spec references:
#   OCPI 2.2.1 — Part I §6.6 (Credentials)
#   OCPI 2.3.0 — Part I §6.6
#
# Effects: none.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./role" as role

# ---- BusinessDetails ---------------------------------------------
#
# Each `CredentialsRole` carries a `business_details` record:
# human-readable name + optional website + optional logo URL. The
# `Image` record below carries the logo metadata when present.

type Image = {
  url       :: Str,
  thumbnail :: Option[Str],
  category  :: Str,
  image_type :: Str,
  width     :: Option[Int],
  height    :: Option[Int],
}

type BusinessDetails = {
  name    :: Str,
  website :: Option[Str],
  logo    :: Option[Image],
}

fn business_details(name :: Str) -> BusinessDetails {
  { name: name, website: None, logo: None }
}

fn business_details_with(
  name    :: Str,
  website :: Option[Str],
  logo    :: Option[Image]
) -> BusinessDetails {
  { name: name, website: website, logo: logo }
}

fn image_to_json(img :: Image) -> jv.Json {
  let base := [
    ("url",      JStr(img.url)),
    ("category", JStr(img.category)),
    ("type",     JStr(img.image_type)),
  ]
  let with_thumb := match img.thumbnail {
    None    => base,
    Some(t) => list.concat(base, [("thumbnail", JStr(t))]),
  }
  let with_w := match img.width {
    None    => with_thumb,
    Some(w) => list.concat(with_thumb, [("width", JInt(w))]),
  }
  let with_h := match img.height {
    None    => with_w,
    Some(h) => list.concat(with_w, [("height", JInt(h))]),
  }
  JObj(with_h)
}

fn business_details_to_json(b :: BusinessDetails) -> jv.Json {
  let base := [("name", JStr(b.name))]
  let with_site := match b.website {
    None    => base,
    Some(w) => list.concat(base, [("website", JStr(w))]),
  }
  let with_logo := match b.logo {
    None    => with_site,
    Some(l) => list.concat(with_site, [("logo", image_to_json(l))]),
  }
  JObj(with_logo)
}

# ---- CredentialsRole ---------------------------------------------
#
# One entry per role the party advertises. A peer that is both a
# CPO and an EMSP ships two entries; each entry pairs a role tag
# with the `(country_code, party_id)` quad and the human-readable
# business details.

type CredentialsRole = {
  role             :: Str,
  business_details :: BusinessDetails,
  party_id         :: Str,
  country_code     :: Str,
}

fn credentials_role(
  role             :: Str,
  business_details :: BusinessDetails,
  party_id         :: Str,
  country_code     :: Str
) -> CredentialsRole {
  {
    role:             role,
    business_details: business_details,
    party_id:         party_id,
    country_code:     country_code,
  }
}

fn credentials_role_to_json(r :: CredentialsRole) -> jv.Json {
  JObj([
    ("role",             JStr(r.role)),
    ("business_details", business_details_to_json(r.business_details)),
    ("party_id",         JStr(r.party_id)),
    ("country_code",     JStr(r.country_code)),
  ])
}

# ---- Credentials object ------------------------------------------
#
# The top-level object exchanged in a credentials POST / PUT.
# `token` is the credentials token the *recipient* of this object
# should use to authenticate future requests to *this* party.

type Credentials = {
  token :: Str,
  url   :: Str,
  roles :: List[CredentialsRole],
}

fn new(token :: Str, url :: Str, roles :: List[CredentialsRole]) -> Credentials {
  { token: token, url: url, roles: roles }
}

fn to_json(c :: Credentials) -> jv.Json {
  JObj([
    ("token", JStr(c.token)),
    ("url",   JStr(c.url)),
    ("roles", JList(list.map(c.roles, credentials_role_to_json))),
  ])
}

# ---- Schemas -----------------------------------------------------
#
# Pydantic-style validators that reject malformed Credentials
# payloads at the framework boundary. Mirrors lex-ocpp's
# pattern: `route.handler_with_schema` runs these before the
# handler ever sees a payload.

fn business_details_schema() -> s.ModelSchema {
  {
    title: "BusinessDetails",
    description: "OCPI — BusinessDetails",
    fields: [
      s.required_str("name",    [StrNonEmpty, StrMaxLen(100)]),
      s.optional(s.required_str("website", [StrMaxLen(255)])),
    ],
  }
}

fn credentials_role_schema() -> s.ModelSchema {
  {
    title: "CredentialsRole",
    description: "OCPI 2.2.1 — Credentials role entry",
    fields: [
      s.required_str("role",             [StrOneOf(role.all_roles_v221())]),
      s.required_object("business_details", business_details_schema()),
      s.required_str("party_id",         [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("country_code",     [StrNonEmpty, StrMaxLen(2)]),
    ],
  }
}

fn credentials_schema_v221() -> s.ModelSchema {
  {
    title: "Credentials",
    description: "OCPI 2.2.1 — Credentials object",
    fields: [
      s.required_str("token", [StrNonEmpty, StrMaxLen(64)]),
      s.required_str("url",   [StrNonEmpty, StrMaxLen(255)]),
      s.required_array("roles",
        KObject(credentials_role_schema()), [ListNonEmpty]),
    ],
  }
}

fn validate_credentials_v221(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(credentials_schema_v221(), j)
}
