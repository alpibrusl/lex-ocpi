# lex-ocpi — OCPI 2.1.1 / 2.2.1 / 2.3.0 CPO server
#
# Multi-version surface: Versions discovery, per-version endpoint
# catalogue, Locations / Sessions / CDRs / Tariffs (CPO sender),
# Tokens PUT + Commands POST (CPO receiver), Credentials POST
# handshake. Spec-required negatives are enforced at the gate:
# missing/wrong-token → 2000, unsupported version → 3002,
# malformed JSON body on a write → 2001.
#
# Filename note: still `cpo_v221.lex` for CI compatibility; the
# server is multi-version. Don't rename without bumping the
# workflow.
#
# Run:
#   lex run --allow-effects net,io,time examples/cpo_v221.lex main
#   curl -H "Authorization: Token cpo-secret" \
#        http://localhost:9100/ocpi/versions

import "std.io"   as io
import "std.net"  as net
import "std.str"  as str
import "std.list" as list
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

fn cpo_base_v211() -> Str { "http://localhost:9100/ocpi/2.1.1" }
fn cpo_base_v221() -> Str { "http://localhost:9100/ocpi/2.2.1" }
fn cpo_base_v230() -> Str { "http://localhost:9100/ocpi/2.3.0" }

# The only token this fake CPO accepts. Real CPOs check against a
# database of registered eMSP credentials; this fixture matches a
# single hard-coded value so the spec-required "wrong token → 2000"
# negative path is testable.
fn valid_cpo_token() -> Str { "cpo-secret" }

# ---- Demo objects -----------------------------------------------

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

# Our own credentials — returned to the eMSP after a successful
# /credentials POST. Real CPOs rotate the token here per the spec's
# bidirectional-credentials handshake; the fake just echoes a
# placeholder.
fn demo_credentials() -> jv.Json {
  JObj([
    ("token", JStr(valid_cpo_token())),
    ("url",   JStr("http://localhost:9100/ocpi/versions")),
    ("roles", JList([
      JObj([
        ("role",             JStr("CPO")),
        ("business_details", JObj([("name", JStr("Example CPO"))])),
        ("country_code",     JStr(cpo_country())),
        ("party_id",         JStr(cpo_party())),
      ]),
    ])),
  ])
}

# ---- Pure handlers ----------------------------------------------

fn get_versions(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([
    versions.version_to_json(versions.version(versions.v211(), cpo_base_v211())),
    versions.version_to_json(versions.version(versions.v221(), cpo_base_v221())),
    versions.version_to_json(versions.version(versions.v230(), cpo_base_v230())),
  ])
}

fn get_version_detail_v211(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  let d := versions.detail(versions.v211(),
    versions.standard_cpo_v221_endpoints(cpo_base_v211()))
  oroute.ok(versions.detail_to_json(d))
}

fn get_version_detail_v221(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  let d := versions.detail(versions.v221(),
    versions.standard_cpo_v221_endpoints(cpo_base_v221()))
  oroute.ok(versions.detail_to_json(d))
}

fn get_version_detail_v230(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  let d := versions.detail(versions.v230(),
    versions.standard_cpo_v221_endpoints(cpo_base_v230()))
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

fn put_token(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  HOkEmpty
}

fn post_command(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok(JObj([
    ("result",  JStr("ACCEPTED")),
    ("timeout", JInt(30)),
  ]))
}

fn post_credentials(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok(demo_credentials())
}

# ---- Registry wiring --------------------------------------------

fn registry() -> oroute.Registry {
  oroute.new()
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.versions(), get_versions)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "version_detail_v211", get_version_detail_v211)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "version_detail", get_version_detail_v221)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), "version_detail_v230", get_version_detail_v230)
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
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.put(), "tokens_by_id", put_token)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.post(), mid.commands(), post_command)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.post(), mid.credentials(), post_credentials)
       }
}

# ---- HTTP adapter ------------------------------------------------
#
# Gate chain (in order):
#   1. check_authorization        Token <b64> present + value matches
#   2. check_unsupported_version  path's /ocpi/{X}/ segment is one we know
#   3. check_body_parseable       JSON body parses on POST/PUT/PATCH
# Falls through to `dispatch_request` only when all three pass.

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
    None      => match check_unsupported_version(req.path, timestamp) {
      Some(err) => err,
      None      => match check_body_parseable(req, timestamp) {
        Some(err) => err,
        None      => dispatch_request(req, timestamp),
      },
    },
  }
  json_response(env.encode(result))
}

# Auth gate. Three failure modes, all map to status_code 2000:
#   - header absent
#   - header present with non-`Token` scheme
#   - header present with `Token <wrong-value>`
fn check_authorization(
  headers   :: Map[Str, Str],
  timestamp :: Str
) -> Option[env.OcpiResponse] {
  let authz := match map.get(headers, "authorization") {
    None    => "",
    Some(v) => v,
  }
  match h.strip_token_prefix(authz) {
    None => Some(env.fail_with_data(
                   ocpi_status.client_error(),
                   "Missing or malformed Authorization header",
                   JNull, timestamp)),
    Some(tok) => if tok == valid_cpo_token() {
                   None
                 } else {
                   Some(env.fail_with_data(
                          ocpi_status.client_error(),
                          "Invalid Authorization token",
                          JNull, timestamp))
                 },
  }
}

# Unsupported-version gate. `/ocpi/9.9.9/locations` returns 3002
# rather than the 2000 generic fallback because the spec carves out
# 3002 specifically for `Unknown / Unsupported version`.
# `/ocpi/versions` (the discovery endpoint, no version segment) is
# exempt.
fn check_unsupported_version(
  path      :: Str,
  timestamp :: Str
) -> Option[env.OcpiResponse] {
  if path == "/ocpi/versions" {
    None
  } else { if not str.starts_with(path, "/ocpi/") {
    None                                # outside the OCPI mount, leave for fallback
  } else {
    let tail := str.slice(path, str.len("/ocpi/"), str.len(path))
    let segs := str.split(tail, "/")
    # Only fire 3002 when the caller actually targeted a versioned
    # module — i.e. /ocpi/{ver}/{something...}. A bare /ocpi/{ver}
    # routes to the version-detail handler, and a bare /ocpi/{junk}
    # (no module segment, junk is not a known version) is a generic
    # unknown-route case and should fall through to the 2000 handler.
    let ver := first_segment(tail)
    if list.len(segs) < 2 {
      None
    } else { if ver == versions.v211() or ver == versions.v221() or ver == versions.v230() {
      None                              # known version
    } else {
      Some(env.fail_with_data(
             ocpi_status.unsupported_version(),
             str.concat("Unsupported version: ", ver),
             JNull, timestamp))
    } }
  } }
}

fn first_segment(s :: Str) -> Str {
  match list.head(str.split(s, "/")) {
    None      => s,
    Some(seg) => seg,
  }
}

# Body-shape gate. Only enforced on writes (POST/PUT/PATCH) and only
# when the body is non-empty — a write with an empty body is
# spec-allowed (e.g. the bodyless Token PUT case).
fn check_body_parseable(
  req       :: Request,
  timestamp :: Str
) -> Option[env.OcpiResponse] {
  if is_write_method(req.method) and not str.is_empty(req.body) {
    match jv.parse(req.body) {
      Ok(_)  => None,
      Err(_) => Some(env.fail_with_data(
                       ocpi_status.invalid_or_missing_parameters(),
                       "Malformed JSON body",
                       JNull, timestamp)),
    }
  } else { None }
}

fn is_write_method(m :: Str) -> Bool {
  m == "POST" or m == "PUT" or m == "PATCH"
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
  } else { if path == "/ocpi/2.1.1" or path == "/ocpi/2.1.1/" {
    Some({ module: "version_detail_v211", params: map.new() })
  } else { if path == "/ocpi/2.2.1" or path == "/ocpi/2.2.1/" {
    Some({ module: "version_detail", params: map.new() })
  } else { if path == "/ocpi/2.3.0" or path == "/ocpi/2.3.0/" {
    Some({ module: "version_detail_v230", params: map.new() })
  } else {
    match strip_version_prefix(path) {
      None       => None,
      Some(rest) => map_versioned_path(rest),
    }
  } } } }
}

fn strip_version_prefix(path :: Str) -> Option[Str] {
  if str.starts_with(path, "/ocpi/2.1.1/") {
    Some(str.slice(path, str.len("/ocpi/2.1.1/"), str.len(path)))
  } else { if str.starts_with(path, "/ocpi/2.2.1/") {
    Some(str.slice(path, str.len("/ocpi/2.2.1/"), str.len(path)))
  } else { if str.starts_with(path, "/ocpi/2.3.0/") {
    Some(str.slice(path, str.len("/ocpi/2.3.0/"), str.len(path)))
  } else {
    None
  } } }
}

fn map_versioned_path(rest :: Str) -> Option[RouteHit] {
  if rest == "locations" {
    Some({ module: mid.locations(), params: map.new() })
  } else { if str.starts_with(rest, "locations/") {
    let loc_id := str.slice(rest, str.len("locations/"), str.len(rest))
    Some({
      module: "location_by_id",
      params: map.set(map.new(), "location_id", loc_id),
    })
  } else { if rest == "sessions" {
    Some({ module: mid.sessions(), params: map.new() })
  } else { if rest == "cdrs" {
    Some({ module: mid.cdrs(), params: map.new() })
  } else { if rest == "tariffs" {
    Some({ module: mid.tariffs(), params: map.new() })
  } else { if rest == "credentials" {
    Some({ module: mid.credentials(), params: map.new() })
  } else { if str.starts_with(rest, "tokens/") {
    let suffix := str.slice(rest, str.len("tokens/"), str.len(rest))
    Some({
      module: "tokens_by_id",
      params: map.set(map.new(), "token_path", suffix),
    })
  } else { if str.starts_with(rest, "commands/") {
    let cmd := str.slice(rest, str.len("commands/"), str.len(rest))
    Some({
      module: mid.commands(),
      params: map.set(map.new(), "command", cmd),
    })
  } else {
    None
  } } } } } } } }
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
  let _ := io.print("CPO v2.1.1/2.2.1/2.3.0  http://localhost:9100/ocpi/versions")
  net.serve_fn(9100, handle)
}
