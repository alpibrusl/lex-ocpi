# lex-ocpi — property-based test driver
#
# Generates schema-conforming random payloads and asserts every
# generated sample validates. The contract: if the schema says a
# payload shape is legal, the validator must accept it. Reuses
# lex-schema's `property.generate` so the generator and validator
# share the same `ModelSchema` source of truth.
#
# Effect: `[random]`. Run via:
#   lex run --allow-effects random tests/test_property.lex run_all

import "std.list"   as list
import "std.str"    as str
import "std.random" as random

import "lex-schema/json_value" as jv
import "lex-schema/property"   as p
import "lex-schema/schema"     as sch

import "../src/credentials"          as creds
import "../src/v221/locations"       as locs
import "../src/v221/sessions"        as sess
import "../src/v221/tokens"          as tokens
import "../src/v221/chargingprofiles" as cp
import "../src/v221/hubclientinfo"   as hub

# ---- Helpers ----------------------------------------------------

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

# Generate one sample, run a validator, assert it accepts.
fn round_trip(
  label :: Str,
  schema :: sch.ModelSchema,
  validator :: (jv.Json) -> Result[jv.Json, List[{ path :: Str, code :: Str, message :: Str }]],
  seed :: Int
) -> [random] Result[Unit, Str] {
  let g := p.generate(schema, random.seed(seed))
  let v := match g { (v1, _) => v1 }
  match validator(v) {
    Ok(_)   => pass(),
    Err(es) => fail(str.concat(label,
      str.concat(": generated payload failed validation: ",
        str.concat(jv.stringify(v), str.concat(" — errors: ",
          int_count(es)))))),
  }
}

fn int_count(es :: List[{ path :: Str, code :: Str, message :: Str }]) -> Str {
  if list.is_empty(es) { "no detail" } else {
    match list.head(es) {
      None    => "no detail",
      Some(e1) => str.concat(e1.path, str.concat(" — ", e1.message)),
    }
  }
}

# ---- Per-validator property tests --------------------------------

fn test_connector_property() -> [random] Result[Unit, Str] {
  round_trip("Connector", locs.connector_schema(),
    locs.validate_connector, 11)
}

fn test_evse_property() -> [random] Result[Unit, Str] {
  round_trip("EVSE", locs.evse_schema(),
    locs.validate_evse, 12)
}

fn test_location_property() -> [random] Result[Unit, Str] {
  round_trip("Location", locs.location_schema(),
    locs.validate_location, 13)
}

fn test_session_property() -> [random] Result[Unit, Str] {
  round_trip("Session", sess.session_schema(),
    sess.validate_session, 14)
}

fn test_token_property() -> [random] Result[Unit, Str] {
  round_trip("Token", tokens.token_schema(),
    tokens.validate_token, 15)
}

fn test_credentials_property() -> [random] Result[Unit, Str] {
  round_trip("Credentials", creds.credentials_schema_v221(),
    creds.validate_credentials_v221, 16)
}

fn test_charging_profile_property() -> [random] Result[Unit, Str] {
  round_trip("ChargingProfile", cp.charging_profile_schema(),
    cp.validate_charging_profile, 17)
}

fn test_client_info_property() -> [random] Result[Unit, Str] {
  round_trip("ClientInfo", hub.client_info_schema(),
    hub.validate_client_info, 18)
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> [random] List[Result[Unit, Str]] {
  [
    test_connector_property(),
    test_evse_property(),
    test_location_property(),
    test_session_property(),
    test_token_property(),
    test_credentials_property(),
    test_charging_profile_property(),
    test_client_info_property(),
  ]
}

fn run_all() -> [random] Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}
