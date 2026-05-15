# lex-ocpi — outbound HTTP client
#
# A CPO that wants to push Sessions/CDRs/Locations to its eMSPs, or
# an eMSP that runs the Credentials handshake against a CPO, calls
# out HTTP. This module bundles `std.http` with the OCPI envelope
# decode + header build pattern so callers don't repeat that
# boilerplate at every call site.
#
# Effects: `[net]` (wire ops only). Pure builders for assembling
# the request — see `with_party_routing`, `with_token`, etc.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.1 (Response Object — decode contract)
#   OCPI 2.2.1 — Part I §4.2 (Request Headers — `Token <b64>`)

import "std.str"   as str
import "std.list"  as list
import "std.map"   as map
import "std.http"  as http
import "std.bytes" as bytes

import "lex-schema/json_value" as jv

import "./envelope" as env
import "./headers"  as h
import "./party"    as party

# ---- HttpError envelope (lifted into our error type) ------------

type ClientError =
    HttpFailed(Str)           # underlying net error
  | BadEnvelope(Str)           # could not decode OCPI envelope
  | OcpiError(env.OcpiResponse) # decoded envelope carrying status_code >= 2000

# ---- Request builders -------------------------------------------
#
# Build a vanilla `HttpRequest` (the std.http record shape) with the
# OCPI eight-headers preloaded. The returned value is a plain
# `HttpRequest` so callers can stack `http.with_header` /
# `http.with_timeout_ms` on top.

fn base_request(method :: Str, url :: Str) -> HttpRequest {
  {
    method:     method,
    url:        url,
    headers:    map.new(),
    body:       None,
    timeout_ms: Some(30000),
  }
}

fn with_token(req :: HttpRequest, token_b64 :: Str) -> HttpRequest {
  http.with_header(req, h.h_authorization(),
    str.concat("Token ", token_b64))
}

fn with_request_id(req :: HttpRequest, request_id :: Str) -> HttpRequest {
  http.with_header(req, h.h_request_id(), request_id)
}

fn with_correlation_id(req :: HttpRequest, correlation_id :: Str) -> HttpRequest {
  http.with_header(req, h.h_correlation_id(), correlation_id)
}

fn with_party_routing(
  req        :: HttpRequest,
  from_party :: party.PartyId,
  to_party   :: party.PartyId
) -> HttpRequest {
  let r1 := http.with_header(req, h.h_from_country_code(), from_party.country_code)
  let r2 := http.with_header(r1,  h.h_from_party_id(),     from_party.party_id)
  let r3 := http.with_header(r2,  h.h_to_country_code(),   to_party.country_code)
  http.with_header(r3,            h.h_to_party_id(),       to_party.party_id)
}

# Attach an OCPI JSON body. The body is encoded inline; callers
# building a payload from a `jv.Json` value pass `jv.stringify(...)`.
fn with_json_body(req :: HttpRequest, body :: Str) -> HttpRequest {
  let with_ct := http.with_header(req, "content-type", "application/json")
  {
    method:     with_ct.method,
    url:        with_ct.url,
    headers:    with_ct.headers,
    body:       Some(bytes.from_str(body)),
    timeout_ms: with_ct.timeout_ms,
  }
}

# ---- Send + decode ----------------------------------------------
#
# Run the request through `http.send`, decode the response body
# into an `OcpiResponse` envelope, and lift transport / decode /
# OCPI-error states into a single `ClientError` ADT. A 1xxx envelope
# returns `Ok(envelope.data)`; a 2xxx/3xxx/4xxx envelope returns
# `Err(OcpiError(envelope))` so callers can read `status_code` /
# `status_message` / `data` for the failure detail.

fn send(req :: HttpRequest) -> [net] Result[jv.Json, ClientError] {
  match http.send(req) {
    Err(_)   => Err(HttpFailed("http.send transport error")),
    Ok(resp) => decode_body(resp.body),
  }
}

fn decode_body(raw :: Bytes) -> Result[jv.Json, ClientError] {
  match bytes.to_str(raw) {
    Err(e) => Err(BadEnvelope(str.concat("response body not UTF-8: ", e))),
    Ok(s)  => match env.parse(s) {
      Err(ee) => Err(BadEnvelope(ee.message)),
      Ok(r)   => if r.status_code >= 1000 and r.status_code < 2000 {
        Ok(r.data)
      } else {
        Err(OcpiError(r))
      },
    },
  }
}

# ---- Convenience: GET with auth ---------------------------------
#
# Most OCPI reads are a single GET against a versions / locations /
# tariffs URL with the credentials token attached. `get_with_token`
# packages the common shape; callers stack `with_party_routing` /
# `with_request_id` on the returned request when needed.

fn get_with_token(url :: Str, token_b64 :: Str) -> [net] Result[jv.Json, ClientError] {
  let req := with_token(base_request("GET", url), token_b64)
  send(req)
}

# ---- Convenience: PUT a JSON body -------------------------------

fn put_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("PUT", url), token_b64),
              body)
  send(req)
}

fn post_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("POST", url), token_b64),
              body)
  send(req)
}

fn patch_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("PATCH", url), token_b64),
              body)
  send(req)
}

fn delete_with_token(url :: Str, token_b64 :: Str) -> [net] Result[jv.Json, ClientError] {
  let req := with_token(base_request("DELETE", url), token_b64)
  send(req)
}
