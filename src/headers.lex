# lex-ocpi — OCPI request headers
#
# Every OCPI request carries a fixed set of headers:
#
#   Authorization:            Token <base64-encoded-credentials-token>
#   X-Request-ID:             <unique per-request id>
#   X-Correlation-ID:         <unique per-correlation id>
#   OCPI-from-country-code:   <ISO-3166 alpha-2>      (functional modules)
#   OCPI-from-party-id:       <3-letter party id>      (functional modules)
#   OCPI-to-country-code:     <ISO-3166 alpha-2>      (functional modules)
#   OCPI-to-party-id:         <3-letter party id>      (functional modules)
#
# The `OCPI-*-{country-code,party-id}` quartet is only required on
# **functional** module requests (Locations, Sessions, CDRs, …).
# Configuration module requests (Versions, Credentials, HubClientInfo)
# omit them.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.2 (Request Headers)
#   OCPI 2.3.0 — Part I §4.2
#
# Effects: none. Parsing / building are pure folds over the
# Map[Str, Str] of HTTP headers.

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "./party" as party

# ---- Datatype ----------------------------------------------------
#
# `OcpiHeaders` carries the eight header values a functional-module
# request needs. Configuration-module callers leave the
# `from` / `to` party id fields as empty `PartyId` records.

type OcpiHeaders = {
  authorization   :: Str,
  request_id      :: Str,
  correlation_id  :: Str,
  from_party      :: party.PartyId,
  to_party        :: party.PartyId,
}

fn new(
  authorization  :: Str,
  request_id     :: Str,
  correlation_id :: Str,
  from_party     :: party.PartyId,
  to_party       :: party.PartyId
) -> OcpiHeaders {
  {
    authorization:  authorization,
    request_id:     request_id,
    correlation_id: correlation_id,
    from_party:     from_party,
    to_party:       to_party,
  }
}

# ---- Header-name constants ---------------------------------------
#
# OCPI header names are case-insensitive on the wire, but most HTTP
# implementations normalize to lowercase. The constants below match
# the lowercase normalized form to simplify lookup.

fn h_authorization()           -> Str { "authorization" }
fn h_request_id()              -> Str { "x-request-id" }
fn h_correlation_id()          -> Str { "x-correlation-id" }
fn h_from_country_code()       -> Str { "ocpi-from-country-code" }
fn h_from_party_id()           -> Str { "ocpi-from-party-id" }
fn h_to_country_code()         -> Str { "ocpi-to-country-code" }
fn h_to_party_id()             -> Str { "ocpi-to-party-id" }

# ---- Parsing -----------------------------------------------------
#
# Read an `OcpiHeaders` value out of a lowercase-keyed header map.
# Missing functional-only headers (`OCPI-from-*`, `OCPI-to-*`) default
# to empty strings rather than failing — the caller is responsible
# for rejecting configuration-only requests that should carry them.

fn from_map(headers :: Map[Str, Str]) -> OcpiHeaders {
  new(
    get_or_empty(headers, h_authorization()),
    get_or_empty(headers, h_request_id()),
    get_or_empty(headers, h_correlation_id()),
    party.new(
      get_or_empty(headers, h_from_country_code()),
      get_or_empty(headers, h_from_party_id())),
    party.new(
      get_or_empty(headers, h_to_country_code()),
      get_or_empty(headers, h_to_party_id())))
}

fn get_or_empty(headers :: Map[Str, Str], key :: Str) -> Str {
  match map.get(headers, key) {
    None    => "",
    Some(v) => v,
  }
}

# ---- Building ----------------------------------------------------
#
# Emit headers ready for an outbound HTTP request. The Map shape
# pairs with `lex-web`'s request builder.

fn to_map(h :: OcpiHeaders) -> Map[Str, Str] {
  let m0 := map.empty()
  let m1 := map.set(m0, h_authorization(),     h.authorization)
  let m2 := map.set(m1, h_request_id(),        h.request_id)
  let m3 := map.set(m2, h_correlation_id(),    h.correlation_id)
  let m4 := map.set(m3, h_from_country_code(), h.from_party.country_code)
  let m5 := map.set(m4, h_from_party_id(),     h.from_party.party_id)
  let m6 := map.set(m5, h_to_country_code(),   h.to_party.country_code)
  map.set(m6, h_to_party_id(),                 h.to_party.party_id)
}

# ---- Authorization token extraction ------------------------------
#
# OCPI's `Authorization: Token <b64>` carries the credentials token
# B64-encoded since OCPI 2.2 (Part I §6.6.2). `strip_token_prefix`
# pulls just the token portion; mismatched prefixes return `None`
# so the caller can answer the request with `2000` /
# `Unauthorized`.

fn strip_token_prefix(authz :: Str) -> Option[Str]
  examples {
    strip_token_prefix("Token abc") => Some("abc"),
    strip_token_prefix("Bearer abc") => None,
    strip_token_prefix("") => None,
  }
{
  let prefix := "Token "
  if str.len(authz) <= str.len(prefix) {
    None
  } else { if str.slice(authz, 0, str.len(prefix)) == prefix {
    Some(str.slice(authz, str.len(prefix), str.len(authz)))
  } else {
    None
  } }
}

# ---- Predicates --------------------------------------------------

fn has_party_routing(h :: OcpiHeaders) -> Bool {
  ! str.is_empty(h.from_party.country_code)
    && ! str.is_empty(h.from_party.party_id)
    && ! str.is_empty(h.to_party.country_code)
    && ! str.is_empty(h.to_party.party_id)
}

fn is_authenticated(h :: OcpiHeaders) -> Bool {
  ! str.is_empty(h.authorization)
}
