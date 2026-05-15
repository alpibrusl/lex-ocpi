# lex-ocpi — minimal OCPI 2.2.1 CPO server
#
# Implements the smallest interoperable surface: Versions discovery
# + Credentials handshake + a single-location read-only Locations
# endpoint. Drop in a real Locations / Sessions / CDRs source via
# the route registry to build a production CPO.
#
# Routing is wired up at the `registry()` constructor — add or
# remove `handler(...)` calls there to extend the surface.
#
# Run:
#   lex run --allow-effects net,io,time examples/cpo_v221.lex main
#   curl -H "Authorization: Token cpo-secret" \
#        http://localhost:9100/ocpi/versions
#   curl -H "Authorization: Token cpo-secret" \
#        http://localhost:9100/ocpi/2.2.1/locations/LOC1
#
# Adversarial scenario:
#   - A client that GETs /ocpi/2.2.1/locations/LOC9 (no such location)
#     gets a 200-status HTTP response carrying an OCPI envelope with
#     `status_code: 2003 ("Unknown Location")`. The HTTP layer is
#     intentionally lenient — OCPI errors travel inside the envelope.
#   - A request with a method/path the registry doesn't know maps to
#     `status_code: 2000 ("Generic client error")` from the dispatcher's
#     unknown-route fallback.

import "std.io"   as io
import "std.net"  as net
import "std.str"  as str
import "std.map"  as map
import "std.time" as time

import "lex-schema/json_value" as jv

import "../src/envelope"        as env
import "../src/headers"         as h
import "../src/route"           as oroute
import "../src/status"          as ocpi_status
import "../src/versions"        as versions
import "../src/module_id"       as mid

# ---- Static configuration ---------------------------------------
#
# A real CPO reads this from config / a database. We hard-code one
# Location for the demo. `party_id` + `country_code` identify this
# CPO to its eMSPs.

fn cpo_country() -> Str { "NL" }
fn cpo_party()   -> Str { "EXM" }

fn cpo_base_v221() -> Str {
  "http://localhost:9100/ocpi/2.2.1"
}

# ---- Demo Location ----------------------------------------------

fn demo_location() -> jv.Json {
  JObj([
    ("country_code", JStr(cpo_country())),
    ("party_id",     JStr(cpo_party())),
    ("id",           JStr("LOC1")),
    ("publish",      JBool(true)),
    ("name",         JStr("Example Garage")),
    ("address",      JStr("Stationsplein 1")),
    ("city",         JStr("Amsterdam")),
    ("country",      JStr("NLD")),
    ("coordinates",  JObj([
      ("latitude",  JStr("52.379")),
      ("longitude", JStr("4.900")),
    ])),
    ("evses",        JList([
      JObj([
        ("uid",          JStr("EVSE1")),
        ("status",       JStr("AVAILABLE")),
        ("connectors",   JList([
          JObj([
            ("id",           JStr("1")),
            ("standard",     JStr("IEC_62196_T2")),
            ("format",       JStr("SOCKET")),
            ("power_type",   JStr("AC_3_PHASE")),
            ("max_voltage",  JInt(400)),
            ("max_amperage", JInt(32)),
            ("last_updated", JStr("2026-05-15T10:00:00Z")),
          ]),
        ])),
        ("last_updated", JStr("2026-05-15T10:00:00Z")),
      ]),
    ])),
    ("time_zone",    JStr("Europe/Amsterdam")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

# ---- Pure handlers (no effects) ---------------------------------
#
# Each handler returns a `HandlerResult` — the dispatcher wraps the
# result in the OCPI envelope. Path params arrive via the
# `OcpiRequest.path_params` Map populated by the HTTP adapter below.

fn get_versions(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([
    versions.version_to_json(
      versions.version(versions.v221(), cpo_base_v221())),
  ])
}

fn get_version_detail(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  let d := versions.detail(versions.v221(),
    versions.standard_cpo_v221_endpoints(cpo_base_v221()))
  oroute.ok(versions.detail_to_json(d))
}

fn get_locations(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_location()])
}

fn get_location_by_id(req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  match map.get(req.path_params, "location_id") {
    None => oroute.fail_with(ocpi_status.invalid_or_missing_parameters(),
      "missing location_id"),
    Some(loc_id) => if loc_id == "LOC1" {
      oroute.ok(demo_location())
    } else {
      oroute.fail_with(ocpi_status.unknown_location(),
        str.concat("Unknown Location: ", loc_id))
    },
  }
}

# ---- Registry wiring --------------------------------------------
#
# Routes are keyed by `(method, module)`; the HTTP adapter below
# converts the URL path into the module name. `version_detail` and
# `location_by_id` are pseudo-modules — they don't appear in
# `module_id.lex` but are dispatched through the same registry.

fn registry() -> oroute.Registry {
  oroute.new()
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.versions(), get_versions)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "version_detail", get_version_detail)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.locations(), get_locations)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "location_by_id", get_location_by_id)
       }
}

# ---- HTTP adapter ------------------------------------------------
#
# `std.net.serve_fn` hands every handler a Request record and expects
# a Response record (both structural — `{ method, path, query, body,
# headers }` in, `{ body, status, headers }` out). We do the URL →
# (module, path_params) mapping here, hand the resulting `OcpiRequest`
# to the OCPI dispatcher, and encode the OCPI envelope into the HTTP
# response body. Effects `[time]` come from stamping the response
# timestamp.

type HttpRequest = {
  body    :: Str,
  method  :: Str,
  path    :: Str,
  query   :: Str,
  headers :: Map[Str, Str],
}

type HttpResponse = {
  body    :: Str,
  status  :: Int,
  headers :: Map[Str, Str],
}

fn json_response(body :: Str) -> HttpResponse {
  {
    body:    body,
    status:  200,
    headers: map.set(map.empty(), "content-type", "application/json"),
  }
}

fn handle(req :: HttpRequest) -> [time] HttpResponse {
  let m := req.method
  let p := req.path
  let routed := match map_url_to_module(p) {
    None        => ocpi_request(m, "unknown", p, map.empty(), req),
    Some(entry) => ocpi_request(m, entry.module, p, entry.params, req),
  }
  let res := oroute.dispatch(registry(), routed, time.now_str())
  json_response(env.encode(res))
}

# ---- URL → (module, path_params) --------------------------------
#
# A tiny URL router. Real implementations layer lex-web's
# pattern-matching router on top; this version keeps the example
# free of cross-package deps so `lex check` works against just
# lex-schema.

type RouteHit = { module :: Str, params :: Map[Str, Str] }

fn map_url_to_module(path :: Str) -> Option[RouteHit] {
  if path == "/ocpi/versions" {
    Some({ module: mid.versions(), params: map.empty() })
  } else { if path == "/ocpi/2.2.1/" || path == "/ocpi/2.2.1" {
    Some({ module: "version_detail", params: map.empty() })
  } else { if path == "/ocpi/2.2.1/locations" {
    Some({ module: mid.locations(), params: map.empty() })
  } else { if str.starts_with(path, "/ocpi/2.2.1/locations/") {
    let loc_id := str.slice(path, str.len("/ocpi/2.2.1/locations/"),
                            str.len(path))
    Some({
      module: "location_by_id",
      params: map.set(map.empty(), "location_id", loc_id),
    })
  } else {
    None
  } } } }
}

fn ocpi_request(
  method      :: Str,
  module_name :: Str,
  path        :: Str,
  params      :: Map[Str, Str],
  req         :: HttpRequest
) -> oroute.OcpiRequest {
  let body := match jv.parse(req.body) {
    Err(_)  => JNull,
    Ok(j)   => j,
  }
  let hdrs := h.from_map(req.headers)
  oroute.request(method, module_name, path, params, map.empty(), hdrs, body)
}

# ---- Entry point ------------------------------------------------

fn main() -> [net, io, time] Nil {
  let _ := io.print("CPO v2.2.1  http://localhost:9100/ocpi/versions")
  net.serve_fn(9100, handle)
}
