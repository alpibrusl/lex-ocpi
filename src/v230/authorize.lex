# lex-ocpi — OCPI 2.3.0 real-time token authorization
#
# Same wire shape as v2.2.1: URL carries `{country_code}/{party_id}/
# {token_uid}`, AuthorizationInfo includes the full Token + optional
# authorization_reference. The shared `AuthorizationResult` ADT +
# decode/encode live in `src/authorize.lex`.
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

fn build_authorize_url(
  base         :: Str,
  country_code :: Str,
  party_id     :: Str,
  token_uid    :: Str
) -> Str
  examples {
    build_authorize_url("https://emsp.example/ocpi/2.3.0/tokens",
                        "NL", "TNM", "RFID-A") =>
      "https://emsp.example/ocpi/2.3.0/tokens/NL/TNM/RFID-A/authorize",
  }
{
  let s1 := str.concat(base, "/")
  let s2 := str.concat(s1, country_code)
  let s3 := str.concat(s2, "/")
  let s4 := str.concat(s3, party_id)
  let s5 := str.concat(s4, "/")
  let s6 := str.concat(s5, token_uid)
  str.concat(s6, "/authorize")
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
  country_code  :: Str,
  party_id      :: Str,
  token_uid     :: Str,
  token_b64     :: Str,
  location_refs :: Option[jv.Json]
) -> [net] Result[auth.AuthorizationResult, client.ClientError] {
  let url  := build_authorize_url(base, country_code, party_id, token_uid)
  let body := build_authorize_body(location_refs)
  match client.post_json(url, body, token_b64) {
    Err(err) => Err(err),
    Ok(j)    => match auth.decode(j) {
      Err(why) => Err(BadEnvelope(why)),
      Ok(r)    => Ok(r),
    },
  }
}
