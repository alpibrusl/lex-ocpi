# lex-ocpi — OCPI 2.1.1 real-time token authorization
#
# Same flow as v2.2.1 (POST /tokens/.../authorize), with the v2.1.1
# URL shape — no country_code / party_id in the path, just the
# token uid:
#
#   POST /ocpi/2.1.1/tokens/{token_uid}/authorize
#
# Token / AuthorizationInfo are flatter in 2.1.1 (see `./tokens`);
# the shared `AuthorizationResult` ADT + decode/encode live in
# `src/authorize.lex`.
#
# Effects: pure for everything except `authorize_token` (`[net]`).

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../authorize" as auth
import "../client"    as client
import "../route"     as route
import "../error"     as oe
import "./tokens"     as tokens

# ---- URL + body builders ----------------------------------------

fn build_authorize_url(base :: Str, token_uid :: Str) -> Str
  examples {
    build_authorize_url("https://emsp.example/ocpi/2.1.1/tokens",
                        "RFID-A") =>
      "https://emsp.example/ocpi/2.1.1/tokens/RFID-A/authorize",
  }
{
  let s1 := str.concat(base, "/")
  let s2 := str.concat(s1, token_uid)
  str.concat(s2, "/authorize")
}

fn build_authorize_body(refs :: Option[jv.Json]) -> Str
  examples {
    build_authorize_body(None) => "{}",
  }
{
  match refs {
    None    => "{}",
    Some(j) => jv.stringify(j),
  }
}

# ---- Receiver-side glue -----------------------------------------

fn body_validator(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  match j {
    JNull         => Ok(j),
    JObj(entries) => if list.is_empty(entries) {
                       Ok(j)
                     } else {
                       tokens.validate_location_references(j)
                     },
    _             => tokens.validate_location_references(j),
  }
}

fn authorize_handler(
  authorize :: (Str, Option[jv.Json]) -> auth.AuthorizationResult
) -> (route.OcpiRequest) -> route.HandlerResult {
  fn (req :: route.OcpiRequest) -> route.HandlerResult {
    match map.get(req.path_params, "token_uid") {
      None => route.fail(oe.invalid_parameters("missing token_uid in path")),
      Some(uid) => {
        let refs := body_to_refs(req.body)
        let result := authorize(uid, refs)
        route.ok(auth.encode(result))
      },
    }
  }
}

fn body_to_refs(j :: jv.Json) -> Option[jv.Json] {
  match j {
    JNull         => None,
    JObj(entries) => if list.is_empty(entries) { None } else { Some(j) },
    _             => Some(j),
  }
}

# ---- Sender-side `[net]` helper ---------------------------------

fn authorize_token(
  base          :: Str,
  token_uid     :: Str,
  token_b64     :: Str,
  location_refs :: Option[jv.Json]
) -> [net] Result[auth.AuthorizationResult, client.ClientError] {
  let url  := build_authorize_url(base, token_uid)
  let body := build_authorize_body(location_refs)
  match client.post_json(url, body, token_b64) {
    Err(err) => Err(err),
    Ok(j)    => match auth.decode(j) {
      Err(why) => Err(BadEnvelope(why)),
      Ok(r)    => Ok(r),
    },
  }
}
