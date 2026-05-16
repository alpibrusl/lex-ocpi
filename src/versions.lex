# lex-ocpi — Versions module
#
# Every OCPI peer ships **two** configuration endpoints under the
# Versions module:
#
#   GET /<base>/versions             → list { version, url }
#   GET /<base>/<version>/           → details { version, endpoints[] }
#
# The two-step discovery hands a client the version list, then the
# per-version endpoint catalogue ("Locations is at https://…,
# Sessions is at …"). Once discovered, the client moves on to the
# Credentials handshake — see `credentials.lex`.
#
# Spec references:
#   OCPI 2.2.1 — Part I §6.1 (Versions)
#   OCPI 2.3.0 — Part I §6.1
#
# Effects: none. Encode / decode are pure folds.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "./module_id"      as mid
import "./interface_role" as iface

# ---- Version-number string constants -----------------------------
#
# Wire-exact spelling of every OCPI version this library targets.
# Use these constants when building a `Version` value or validating
# inbound `version` strings.

fn v211() -> Str { "2.1.1" }
fn v221() -> Str { "2.2.1" }
fn v230() -> Str { "2.3.0" }

fn all_versions() -> List[Str] { [v211(), v221(), v230()] }

# ---- Top-level "version" entry -----------------------------------
#
# A single entry in the `GET /versions` response: `{ version, url }`.
# `url` is the absolute URL pointing at the per-version detail
# endpoint (`GET /<base>/<version>/`).

type Version = {
  version :: Str,
  url     :: Str,
}

fn version(v :: Str, url :: Str) -> Version
  examples {
    version("2.2.1", "https://cpo.example.com/ocpi/2.2.1") =>
      { version: "2.2.1", url: "https://cpo.example.com/ocpi/2.2.1" },
  }
{
  { version: v, url: url }
}

fn version_to_json(v :: Version) -> jv.Json {
  JObj([
    ("version", JStr(v.version)),
    ("url",     JStr(v.url)),
  ])
}

# ---- Per-version endpoint entry ----------------------------------
#
# An `Endpoint` advertises a single module / interface-role pairing:
# `{ identifier: "locations", role: "SENDER", url: "https://…" }`.
# OCPI 2.2+ adds an optional `role` field; 2.1.1 has only
# `identifier` + `url` (no Sender/Receiver split).

type Endpoint = {
  identifier :: Str,
  role       :: Str,
  url        :: Str,
}

fn endpoint(identifier :: Str, role :: Str, url :: Str) -> Endpoint {
  { identifier: identifier, role: role, url: url }
}

fn endpoint_sender(identifier :: Str, url :: Str) -> Endpoint
  examples {
    endpoint_sender("locations", "https://x/locations") =>
      { identifier: "locations", role: "SENDER", url: "https://x/locations" },
  }
{
  endpoint(identifier, iface.sender(), url)
}

fn endpoint_receiver(identifier :: Str, url :: Str) -> Endpoint
  examples {
    endpoint_receiver("credentials", "https://x/credentials") =>
      { identifier: "credentials", role: "RECEIVER", url: "https://x/credentials" },
  }
{
  endpoint(identifier, iface.receiver(), url)
}

fn endpoint_to_json(e :: Endpoint) -> jv.Json {
  JObj([
    ("identifier", JStr(e.identifier)),
    ("role",       JStr(e.role)),
    ("url",        JStr(e.url)),
  ])
}

# ---- Version-detail response -------------------------------------
#
# `GET /<base>/<version>/` returns
#   { version: "2.2.1", endpoints: [{ identifier, role, url }, …] }
# inside the standard `data` envelope. Build a `VersionDetail` once
# at server startup; it's a pure value.

type VersionDetail = {
  version   :: Str,
  endpoints :: List[Endpoint],
}

fn detail(v :: Str, endpoints :: List[Endpoint]) -> VersionDetail {
  { version: v, endpoints: endpoints }
}

fn detail_to_json(d :: VersionDetail) -> jv.Json {
  JObj([
    ("version",   JStr(d.version)),
    ("endpoints", JList(list.map(d.endpoints, endpoint_to_json))),
  ])
}

# ---- Builders for a stock CPO / EMSP surface ----------------------
#
# Convenience: build an endpoint list for a v2.2.1 CPO that
# implements the standard module set. Real implementations will
# replace this with their own list — but the stock helpers are
# useful for examples and tests.

fn standard_cpo_v221_endpoints(base :: Str) -> List[Endpoint] {
  [
    endpoint_receiver(mid.credentials(),     concat3(base, "/", "credentials")),
    endpoint_sender(  mid.locations(),       concat3(base, "/", "locations")),
    endpoint_sender(  mid.sessions(),        concat3(base, "/", "sessions")),
    endpoint_sender(  mid.cdrs(),            concat3(base, "/", "cdrs")),
    endpoint_sender(  mid.tariffs(),         concat3(base, "/", "tariffs")),
    endpoint_receiver(mid.tokens(),          concat3(base, "/", "tokens")),
    endpoint_receiver(mid.commands(),        concat3(base, "/", "commands")),
  ]
}

fn standard_emsp_v221_endpoints(base :: Str) -> List[Endpoint] {
  [
    endpoint_receiver(mid.credentials(),     concat3(base, "/", "credentials")),
    endpoint_receiver(mid.locations(),       concat3(base, "/", "locations")),
    endpoint_receiver(mid.sessions(),        concat3(base, "/", "sessions")),
    endpoint_receiver(mid.cdrs(),            concat3(base, "/", "cdrs")),
    endpoint_receiver(mid.tariffs(),         concat3(base, "/", "tariffs")),
    endpoint_sender(  mid.tokens(),          concat3(base, "/", "tokens")),
    endpoint_sender(  mid.commands(),        concat3(base, "/", "commands")),
  ]
}

# ---- Internal helper ---------------------------------------------

fn concat3(a :: Str, b :: Str, c :: Str) -> Str {
  str.concat(a, str.concat(b, c))
}
