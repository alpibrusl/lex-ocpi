# lex-ocpi — party identification (country_code + party_id)
#
# An OCPI party is uniquely identified by the pair
# `(country_code, party_id)`. The country code is a two-letter
# ISO-3166-1 alpha-2 string; the party_id is a three-letter
# uppercase ID issued by the registry (eviding / GIREVE / etc.).
#
# The pair shows up in:
#   - `CredentialsRole` (Credentials module)
#   - HTTP request headers (`OCPI-from-country-code`, `OCPI-from-party-id`,
#     `OCPI-to-country-code`, `OCPI-to-party-id`)
#   - Compound IDs (`Token.uid`, `Location.country_code` + `Location.party_id`)
#
# Spec references:
#   OCPI 2.2.1 — Part I §3.4 (Country code), §3.5 (Party_id)
#
# Effects: none.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

# ---- Datatype ----------------------------------------------------

type PartyId = {
  country_code :: Str,
  party_id     :: Str,
}

fn new(country_code :: Str, party_id :: Str) -> PartyId {
  { country_code: country_code, party_id: party_id }
}

# ---- Equality ----------------------------------------------------

fn eq(a :: PartyId, b :: PartyId) -> Bool {
  a.country_code == b.country_code and a.party_id == b.party_id
}

# ---- Encoding ----------------------------------------------------
#
# `to_json` lays the pair down into a JSON object using OCPI's
# canonical field names. Used by the Credentials module and as a
# building block for compound objects that embed a party reference.

fn to_json(p :: PartyId) -> jv.Json {
  JObj([
    ("country_code", JStr(p.country_code)),
    ("party_id",     JStr(p.party_id)),
  ])
}

fn from_json(j :: jv.Json) -> Option[PartyId] {
  match jv.as_obj(j) {
    None => None,
    Some(_) => match jv.get_field(j, "country_code") {
      None => None,
      Some(cc_j) => match jv.as_str(cc_j) {
        None => None,
        Some(cc) => match jv.get_field(j, "party_id") {
          None => None,
          Some(pid_j) => match jv.as_str(pid_j) {
            None => None,
            Some(pid) => Some(new(cc, pid)),
          },
        },
      },
    },
  }
}

# ---- Display -----------------------------------------------------

fn display(p :: PartyId) -> Str
  examples {
    display({ country_code: "NL", party_id: "TNM" }) => "NL*TNM",
  }
{
  str.concat(p.country_code, str.concat("*", p.party_id))
}
