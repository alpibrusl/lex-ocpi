# lex-ocpi — OCPI 2.2.1 CPO server
#
# Implements the v2.2.1 surface this library currently exercises:
# Versions discovery + Locations + Sessions + CDRs + Tariffs.
# Drop in real Sessions / CDRs / Tariffs sources via the route
# registry to build a production CPO.
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
# Adversarial scenarios:
#   - Request without `Authorization` (or with a non-`Token` scheme)
#     gets a 200-status HTTP response carrying an OCPI envelope with
#     `status_code: 2000 ("Generic client error")`. The HTTP layer
#     stays 200 — OCPI errors travel inside the envelope.
#   - GET /ocpi/2.2.1/locations/LOC9 (no such location) returns the
#     spec-shaped `2003 ("Unknown Location")` envelope.
#   - A request with a method/path the registry doesn't know maps to
#     `status_code: 2000` from the dispatcher's unknown-route fallback.

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

# ---- Demo Session (OCPI 2.2.1 §9) ------------------------------

fn demo_session() -> jv.Json {
  JObj([
    ("country_code",     JStr(cpo_country())),
    ("party_id",         JStr(cpo_party())),
    ("id",               JStr("SESS1")),
    ("start_date_time",  JStr("2026-05-15T10:00:00Z")),
    ("kwh",              JFloat(15.5)),
    ("cdr_token",        JObj([
      ("country_code", JStr("DE")),
      ("party_id",     JStr("ABC")),
      ("uid",          JStr("RFID-A")),
      ("type",         JStr("RFID")),
      ("contract_id",  JStr("DE-ABC-C12345-T")),
    ])),
    ("auth_method",      JStr("WHITELIST")),
    ("location_id",      JStr("LOC1")),
    ("evse_uid",         JStr("EVSE1")),
    ("connector_id",     JStr("1")),
    ("currency",         JStr("EUR")),
    ("status",           JStr("ACTIVE")),
    ("last_updated",     JStr("2026-05-15T10:00:00Z")),
  ])
}

# ---- Demo CDR (OCPI 2.2.1 §10) ---------------------------------

fn demo_cdr() -> jv.Json {
  JObj([
    ("country_code",     JStr(cpo_country())),
    ("party_id",         JStr(cpo_party())),
    ("id",               JStr("CDR1")),
    ("start_date_time",  JStr("2026-05-15T10:00:00Z")),
    ("end_date_time",    JStr("2026-05-15T11:00:00Z")),
    ("cdr_token",        JObj([
      ("country_code", JStr("DE")),
      ("party_id",     JStr("ABC")),
      ("uid",          JStr("RFID-A")),
      ("type",         JStr("RFID")),
      ("contract_id",  JStr("DE-ABC-C12345-T")),
    ])),
    ("auth_method",      JStr("WHITELIST")),
    ("cdr_location",     JObj([
      ("id",                    JStr("LOC1")),
      ("address",               JStr("Stationsplein 1")),
      ("city",                  JStr("Amsterdam")),
      ("country",               JStr("NLD")),
      ("coordinates",           JObj([
        ("latitude",  JStr("52.379")),
        ("longitude", JStr("4.900")),
      ])),
      ("evse_uid",              JStr("EVSE1")),
      ("evse_id",               JStr("NL*EXM*E001")),
      ("connector_id",          JStr("1")),
      ("connector_standard",    JStr("IEC_62196_T2")),
      ("connector_format",      JStr("SOCKET")),
      ("connector_power_type",  JStr("AC_3_PHASE")),
    ])),
    ("currency",         JStr("EUR")),
    ("charging_periods", JList([
      JObj([
        ("start_date_time", JStr("2026-05-15T10:00:00Z")),
        ("dimensions",      JList([
          JObj([
            ("type",   JStr("ENERGY")),
            ("volume", JFloat(15.5)),
          ]),
        ])),
      ]),
    ])),
    ("total_cost",       JObj([("excl_vat", JFloat(5.50))])),
    ("total_energy",     JFloat(15.5)),
    ("total_time",       JFloat(1.0)),
    ("last_updated",     JStr("2026-05-15T10:00:00Z")),
  ])
}

# ---- Demo Tariff (OCPI 2.2.1 §11) ------------------------------

fn demo_tariff() -> jv.Json {
  JObj([
    ("country_code", JStr(cpo_country())),
    ("party_id",     JStr(cpo_party())),
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

# ---- Pure handlers (no effects) ---------------------------------

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

fn get_sessions(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_session()])
}

fn get_cdrs(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_cdr()])
}

fn get_tariffs(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_tariff()])
}

# ---- Registry wiring --------------------------------------------

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
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.sessions(), get_sessions)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.cdrs(), get_cdrs)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.tariffs(), get_tariffs)
       }
}

# ---- HTTP adapter ------------------------------------------------

fn json_response(body :: Str) -> Response {
  {
    body:    BodyStr(body),
    status:  200,
    headers: map.set(map.new(), "content-type", "application/json"),
  }
}

fn handle(req :: Request) -> [time] Response {
  let timestamp := time.now_str()
  let result := match check_authorization(req.headers, timestamp) {
    Some(err) => err,
    None      => dispatch_request(req, timestamp),
  }
  json_response(env.encode(result))
}

# Auth gate: every request must carry `Authorization: Token <b64>`.
# Returns `Some(2000 envelope)` to short-circuit when absent or
# malformed; `None` lets the request fall through to dispatch.
# Real CPOs additionally check that the token matches one of the
# registered eMSPs' credentials; this fixture only checks shape.
fn check_authorization(
  headers   :: Map[Str, Str],
  timestamp :: Str
) -> Option[env.OcpiResponse] {
  let authz := match map.get(headers, "authorization") {
    None    => "",
    Some(v) => v,
  }
  match h.strip_token_prefix(authz) {
    Some(_) => None,                                # well-formed
    None    => Some(env.fail_with_data(
                      ocpi_status.client_error(),
                      "Missing or malformed Authorization header",
                      JNull,
                      timestamp)),
  }
}

fn dispatch_request(req :: Request, timestamp :: Str) -> env.OcpiResponse {
  let m := req.method
  let p := req.path
  let routed := match map_url_to_module(p) {
    None        => ocpi_request(m, "unknown", p, map.new(), req),
    Some(entry) => ocpi_request(m, entry.module, p, entry.params, req),
  }
  oroute.dispatch(registry(), routed, timestamp)
}

# ---- URL → (module, path_params) --------------------------------

type RouteHit = { module :: Str, params :: Map[Str, Str] }

fn map_url_to_module(path :: Str) -> Option[RouteHit] {
  if path == "/ocpi/versions" {
    Some({ module: mid.versions(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/" or path == "/ocpi/2.2.1" {
    Some({ module: "version_detail", params: map.new() })
  } else { if path == "/ocpi/2.2.1/locations" {
    Some({ module: mid.locations(), params: map.new() })
  } else { if str.starts_with(path, "/ocpi/2.2.1/locations/") {
    let loc_id := str.slice(path, str.len("/ocpi/2.2.1/locations/"),
                            str.len(path))
    Some({
      module: "location_by_id",
      params: map.set(map.new(), "location_id", loc_id),
    })
  } else { if path == "/ocpi/2.2.1/sessions" {
    Some({ module: mid.sessions(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/cdrs" {
    Some({ module: mid.cdrs(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/tariffs" {
    Some({ module: mid.tariffs(), params: map.new() })
  } else {
    None
  } } } } } } }
}

fn ocpi_request(
  method      :: Str,
  module_name :: Str,
  path        :: Str,
  params      :: Map[Str, Str],
  req         :: Request
) -> oroute.OcpiRequest {
  let body := match jv.parse(req.body) {
    Err(_)  => JNull,
    Ok(j)   => j,
  }
  let hdrs := h.from_map(req.headers)
  oroute.request(method, module_name, path, params, map.new(), hdrs, body)
}

# ---- Entry point ------------------------------------------------

fn main() -> [net, io, time] Nil {
  let _ := io.print("CPO v2.2.1  http://localhost:9100/ocpi/versions")
  net.serve_fn(9100, handle)
}
