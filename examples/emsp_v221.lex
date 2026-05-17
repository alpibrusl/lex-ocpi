# lex-ocpi — minimal OCPI 2.2.1 eMSP server
#
# Mirror of `examples/cpo_v221.lex` for the eMSP side. Listens on
# port 9101, exposes:
#
#   GET  /ocpi/versions                                    → version list
#   GET  /ocpi/2.2.1                                       → endpoint catalogue
#   POST /ocpi/2.2.1/tokens/{cc}/{pid}/{uid}/authorize     → AuthorizationInfo
#   GET  /ocpi/2.2.1/tariffs                                → [demo tariff]
#
# The authorize decision is a fixture: RFID-A / RFID-B are ALLOWED,
# RFID-C is BLOCKED, everything else is NOT_ALLOWED. Real eMSPs
# replace `fake_authorize` with a database / billing-system lookup.
#
# Run:
#   lex run --allow-effects net,io,time examples/emsp_v221.lex main
#
# Companion to `examples/cpo_v221.lex` and the CI conformance loop
# (see `conformance/emsp_harness.lex`).

import "std.io"   as io
import "std.net"  as net
import "std.str"  as str
import "std.list" as list
import "std.map"  as map
import "std.time" as time

import "lex-schema/json_value" as jv

import "../src/authorize"      as auth
import "../src/envelope"       as env
import "../src/headers"        as h
import "../src/route"          as oroute
import "../src/status"         as ocpi_status
import "../src/versions"       as versions
import "../src/module_id"      as mid
import "../src/v221/authorize" as auth221

# ---- Static configuration ---------------------------------------

fn emsp_country() -> Str { "DE" }
fn emsp_party()   -> Str { "ABC" }

fn emsp_base_v221() -> Str {
  "http://localhost:9101/ocpi/2.2.1"
}

# ---- Demo authorize fixture --------------------------------------
#
# RFID-A / RFID-B are good cards; RFID-C is blocked; anything else
# is `NOT_ALLOWED`. Payload mirrors the wire shape
# `AuthorizationInfo` — we omit the optional `token` /
# `authorization_reference` / `location` fields here.

fn fake_authorize(
  uid  :: Str,
  _refs :: Option[jv.Json]
) -> auth.AuthorizationResult {
  if uid == "RFID-A" or uid == "RFID-B" {
    Allowed(JObj([("allowed", JStr(auth.allowed_str()))]))
  } else { if uid == "RFID-C" {
    Blocked(JObj([("allowed", JStr(auth.blocked_str()))]))
  } else {
    NotAllowed(JObj([("allowed", JStr(auth.not_allowed_str()))]))
  } }
}

# ---- Demo tariff -------------------------------------------------
#
# Bare minimum to make the spec validator happy on the receiver
# side: one TariffElement with one PriceComponent (ListNonEmpty).
# Real eMSPs pull this from a tariff catalogue.

fn demo_tariff() -> jv.Json {
  JObj([
    ("country_code", JStr(emsp_country())),
    ("party_id",     JStr(emsp_party())),
    ("id",           JStr("TARIFF1")),
    ("currency",     JStr("EUR")),
    ("elements",     JList([
      JObj([
        ("price_components", JList([
          JObj([
            ("type",      JStr("ENERGY")),
            ("price",     JFloat(0.30)),
            ("step_size", JInt(1)),
          ]),
        ])),
      ]),
    ])),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

# ---- Pure handlers ----------------------------------------------

fn get_versions(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([
    versions.version_to_json(
      versions.version(versions.v221(), emsp_base_v221())),
  ])
}

fn get_version_detail(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  let d := versions.detail(versions.v221(),
    versions.standard_emsp_v221_endpoints(emsp_base_v221()))
  oroute.ok(versions.detail_to_json(d))
}

fn get_tariffs(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_tariff()])
}

# ---- Registry wiring --------------------------------------------
#
# `authorize_handler` from `src/v221/authorize.lex` produces a
# route-shaped handler from a pure `(uid, refs) -> AuthorizationResult`
# function. We just register the result under the synthetic
# `"token_authorize"` module name; the URL router maps the
# `/tokens/{cc}/{pid}/{uid}/authorize` path onto it.

fn registry() -> oroute.Registry {
  oroute.new()
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.versions(), get_versions)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "version_detail", get_version_detail)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.post(), "token_authorize",
           auth221.authorize_handler(fake_authorize))
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.tariffs(), get_tariffs)
       }
}

# ---- HTTP adapter -----------------------------------------------

fn json_response(body :: Str) -> Response {
  {
    body:    BodyStr(body),
    status:  200,
    headers: map.set(map.new(), "content-type", "application/json"),
  }
}

fn handle(req :: Request) -> [time] Response {
  let m := req.method
  let p := req.path
  let routed := match map_url_to_module(p) {
    None        => ocpi_request(m, "unknown", p, map.new(), req),
    Some(entry) => ocpi_request(m, entry.module, p, entry.params, req),
  }
  let res := oroute.dispatch(registry(), routed, time.now_str())
  json_response(env.encode(res))
}

# ---- URL → (module, path_params) --------------------------------

type RouteHit = { module :: Str, params :: Map[Str, Str] }

fn map_url_to_module(path :: Str) -> Option[RouteHit] {
  if path == "/ocpi/versions" {
    Some({ module: mid.versions(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/" or path == "/ocpi/2.2.1" {
    Some({ module: "version_detail", params: map.new() })
  } else { if path == "/ocpi/2.2.1/tariffs" {
    Some({ module: mid.tariffs(), params: map.new() })
  } else { if is_authorize_path(path) {
    let uid := extract_token_uid(path)
    Some({
      module: "token_authorize",
      params: map.set(map.new(), "token_uid", uid),
    })
  } else {
    None
  } } } }
}

# `/ocpi/2.2.1/tokens/{cc}/{pid}/{uid}/authorize`
fn is_authorize_path(path :: Str) -> Bool {
  str.starts_with(path, "/ocpi/2.2.1/tokens/")
    and str.ends_with(path, "/authorize")
}

fn ends_with_authorize(s :: Str) -> Bool {
  str.ends_with(s, "/authorize")
}

# Extract `{uid}` from `/ocpi/2.2.1/tokens/{cc}/{pid}/{uid}/authorize`
# by stripping the prefix and `/authorize` suffix, then taking the
# last `/`-separated segment of what remains. `cc` is 2 chars and
# `pid` is 3 chars per spec, so the layout is fixed.
fn extract_token_uid(path :: Str) -> Str {
  let prefix := "/ocpi/2.2.1/tokens/"
  let suffix := "/authorize"
  let inner := str.slice(path, str.len(prefix), str.len(path) - str.len(suffix))
  # inner = "cc/pid/uid" — take the last segment
  let parts := str.split(inner, "/")
  match list.head(list.reverse(parts)) {
    None    => "",
    Some(u) => u,
  }
}

fn ocpi_request(
  method      :: Str,
  module_name :: Str,
  path        :: Str,
  params      :: Map[Str, Str],
  req         :: Request
) -> oroute.OcpiRequest {
  let body := match jv.parse(req.body) {
    Err(_) => JNull,
    Ok(j)  => j,
  }
  let hdrs := h.from_map(req.headers)
  oroute.request(method, module_name, path, params, map.new(), hdrs, body)
}

# ---- Entry point ------------------------------------------------

fn main() -> [net, io, time] Nil {
  let _ := io.print("eMSP v2.2.1  http://localhost:9101/ocpi/versions")
  net.serve_fn(9101, handle)
}
