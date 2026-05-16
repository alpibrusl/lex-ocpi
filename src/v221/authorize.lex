# lex-ocpi — OCPI 2.2.1 real-time token authorization
#
# Models the `POST /tokens/{country_code}/{party_id}/{token_uid}/authorize`
# flow that runs before every charge session start. The CPO holds an
# RFID token presented at the charger, asks the eMSP "is this token
# good for this location right now?", and the eMSP returns an
# `AuthorizationInfo` carrying the decision plus an optional
# `LocationReferences` constraint.
#
# The shared `AuthorizationResult` ADT + decode/encode live in
# `src/authorize.lex`. This module adds the per-version bits:
#
#   1. `build_authorize_url(base, country, party, uid)` — pure URL
#      builder for the canonical v2.2.1 path shape.
#   2. `build_authorize_body(refs)` — pure body builder; missing
#      `LocationReferences` becomes `{}` per spec.
#   3. `body_validator(j)` — accepts null + empty `{}` (spec-allowed
#      "any-location"), otherwise delegates to
#      `tokens.validate_location_references`. Exposed so callers wire
#      it via `route.handler_with_schema`.
#   4. `authorize_handler(authorize)` — receiver-side glue: turns a
#      pure `(token_uid, Option[location_refs]) -> AuthorizationResult`
#      into a `route.Handler`.
#   5. `authorize_token(...)` — sender-side `[net]` helper. CPO
#      calls this; result is the typed `AuthorizationResult` or a
#      `client.ClientError`.
#
# Spec references:
#   OCPI 2.2.1 — Part III §12.4.4 (Tokens — POST authorize)
#   OCPI 2.2.1 — Part III §12.5.1 (AuthorizationInfo object)
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
    build_authorize_url("https://emsp.example/ocpi/2.2.1/tokens",
                        "NL", "TNM", "RFID-A") =>
      "https://emsp.example/ocpi/2.2.1/tokens/NL/TNM/RFID-A/authorize",
  }
{
  # str.concat is 2-arg; fold the path segments left-to-right.
  let s1 := str.concat(base, "/")
  let s2 := str.concat(s1, country_code)
  let s3 := str.concat(s2, "/")
  let s4 := str.concat(s3, party_id)
  let s5 := str.concat(s4, "/")
  let s6 := str.concat(s5, token_uid)
  str.concat(s6, "/authorize")
}

# `Option<LocationReferences>` — None becomes `{}`, Some(j) becomes
# `j` stringified. The empty-body case is the "any location" form
# the spec allows when the CPO has no constraint to communicate.
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
  # Empty body / null body is legal — the spec allows the CPO to
  # omit LocationReferences when it has no per-location constraint.
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

# Pull a LocationReferences value out of the request body. Null
# body and empty `{}` both surface as `None` (spec-allowed
# "any-location" form); any other shape passes through as Some.
fn body_to_refs(j :: jv.Json) -> Option[jv.Json] {
  match j {
    JNull         => None,
    JObj(entries) => if list.is_empty(entries) { None } else { Some(j) },
    _             => Some(j),
  }
}

# ---- Sender-side `[net]` helper ---------------------------------
#
# Build the URL, build the body, post it with the eMSP's token,
# decode the response into the typed AuthorizationResult.
#
# `base` is the eMSP's tokens endpoint without trailing slash —
# typically `<peer_root>/tokens`, where peer_root came from the
# version-detail response.

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
