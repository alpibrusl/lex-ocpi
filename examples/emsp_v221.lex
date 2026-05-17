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
import "std.conc" as conc

import "lex-schema/json_value" as jv

import "../src/authorize"      as auth
import "../src/envelope"       as env
import "../src/headers"        as h
import "../src/route"          as oroute
import "../src/status"         as ocpi_status
import "../src/versions"       as versions
import "../src/module_id"      as mid
import "../src/v221/authorize" as auth221
import "../src/v221/cdrs"      as cdrs

# ---- Static configuration ---------------------------------------

fn emsp_country() -> Str { "DE" }
fn emsp_party()   -> Str { "ABC" }

fn emsp_base_v221() -> Str {
  "http://localhost:9101/ocpi/2.2.1"
}

# The only token this fake eMSP accepts. Real eMSPs validate against
# the registered CPO credentials database; the fixture matches a
# single hard-coded value so the spec-required negatives (missing /
# wrong token → 2000) are testable.
fn valid_emsp_token() -> Str { "emsp-secret" }

# ---- Async-command callback recorder ----------------------------
#
# OCPI commands flow: the eMSP POSTs `START_SESSION` to the CPO; the
# CPO returns 1000 ACCEPTED synchronously; later the CPO POSTs a
# `CommandResult` to the `response_url` the eMSP supplied. To make
# the round-trip observable, the fake eMSP exposes a small recorder:
#
#   POST /callback  — stash the inbound body (raw JSON string)
#   GET  /callback  — return the latest stashed body, or `null`
#
# State lives in a `std.conc` actor so concurrent POSTs serialize
# safely. Only the latest body is retained — the harness asserts on
# the most-recent CommandResult, not history.

type CbState = { last :: Option[Str] }

type CbMsg =
    CbStore(Str)
  | CbFetch

type CbReply =
    CbDone
  | CbLatest(Option[Str])

fn cb_handler(state :: CbState, msg :: CbMsg) -> (CbState, CbReply) {
  match msg {
    CbStore(s) => ({ last: Some(s) }, CbDone),
    CbFetch    => (state, CbLatest(state.last)),
  }
}

fn cb_store(actor :: Actor[CbState], body :: Str) -> [concurrent] Unit {
  let _ := conc.tell(actor, CbStore(body))
  ()
}

fn cb_latest(actor :: Actor[CbState]) -> [concurrent] Option[Str] {
  match conc.ask(actor, CbFetch) {
    CbLatest(o) => o,
    CbDone      => None,
  }
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

# eMSP-as-sender: the Tokens module spec places the eMSP on the
# sender side. CPOs GET /tokens to refresh their local token cache.
# A minimal-but-spec-shaped Token entry satisfies the validator on
# the receiver side.
fn demo_token() -> jv.Json {
  JObj([
    ("country_code", JStr(emsp_country())),
    ("party_id",     JStr(emsp_party())),
    ("uid",          JStr("RFID-A")),
    ("type",         JStr("RFID")),
    ("contract_id",  JStr("DE-ABC-C12345-T")),
    ("issuer",       JStr("Example eMSP")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn get_tokens(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  oroute.ok_list([demo_token()])
}

# CPO push CDR → eMSP. The cdr validator runs at the route gate;
# a parseable-but-invalid body surfaces as 2001 with the violation
# list in `data`. On a well-formed CDR we just return an empty 1000
# envelope (real eMSPs would persist the CDR for billing).
fn post_cdr(_req :: oroute.OcpiRequest) -> oroute.HandlerResult {
  HOkEmpty
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
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler_with_schema(r, oroute.post(), mid.cdrs(),
           cdrs.validate_cdr, post_cdr)
       }
    |> fn (r :: oroute.Registry) -> oroute.Registry {
         oroute.handler(r, oroute.get(), mid.tokens(), get_tokens)
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

fn handle(actor :: Actor[CbState], req :: Request) -> [time, concurrent] Response {
  let timestamp := time.now_str()
  if is_callback_post(req)   { handle_cb_post(actor, req, timestamp) }
  else { if is_callback_get(req) { handle_cb_get(actor, timestamp) }
  else { match check_authorization(req.headers, timestamp) {
    Some(err) => json_response(env.encode(err)),
    None      => match check_unsupported_version(req.path, timestamp) {
      Some(err) => json_response(env.encode(err)),
      None      => match check_body_parseable(req, timestamp) {
        Some(err) => json_response(env.encode(err)),
        None      => json_response(env.encode(dispatch_request(req, timestamp))),
      },
    },
  } } }
}

# Callback endpoints are intentionally OUTSIDE the OCPI auth gate —
# the CPO's outbound callback doesn't carry our credentials token,
# and a real eMSP would key callbacks by the `response_url` they
# themselves chose at the time of dispatch.
fn is_callback_post(req :: Request) -> Bool {
  req.method == "POST" and req.path == "/callback"
}

fn is_callback_get(req :: Request) -> Bool {
  req.method == "GET" and req.path == "/callback"
}

fn handle_cb_post(
  actor     :: Actor[CbState],
  req       :: Request,
  timestamp :: Str
) -> [concurrent] Response {
  let _ := cb_store(actor, req.body)
  json_response(env.encode(env.ok_empty(timestamp)))
}

fn handle_cb_get(
  actor     :: Actor[CbState],
  timestamp :: Str
) -> [concurrent] Response {
  let payload := match cb_latest(actor) {
    None    => JNull,
    Some(s) => match jv.parse(s) {
      Err(_) => JStr(s),               # surface as-is if not JSON
      Ok(j)  => j,
    },
  }
  json_response(env.encode(env.ok(payload, timestamp)))
}

fn dispatch_request(req :: Request, timestamp :: Str) -> env.OcpiResponse {
  let m := req.method
  let p := req.path
  let routed := match map_url_to_module(p) {
    None        => ocpi_request(m, "unknown",    p, map.new(),    req),
    Some(entry) => ocpi_request(m, entry.module, p, entry.params, req),
  }
  oroute.dispatch(registry(), routed, timestamp)
}

# Auth gate. Three failure modes, all map to 2000:
#   - header absent
#   - non-`Token` scheme
#   - `Token <wrong-value>`
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
    Some(tok) => if tok == valid_emsp_token() {
                   None
                 } else {
                   Some(env.fail_with_data(
                          ocpi_status.client_error(),
                          "Invalid Authorization token",
                          JNull, timestamp))
                 },
  }
}

# Unsupported-version gate. v2.2.1 is the only version this fixture
# advertises; targeted hits to any other versioned module path
# return 3002. `/ocpi/versions` discovery and bare `/ocpi/{ver}`
# detail are exempt.
fn check_unsupported_version(
  path      :: Str,
  timestamp :: Str
) -> Option[env.OcpiResponse] {
  if path == "/ocpi/versions" {
    None
  } else { if not str.starts_with(path, "/ocpi/") {
    None
  } else {
    let tail := str.slice(path, str.len("/ocpi/"), str.len(path))
    let segs := str.split(tail, "/")
    let ver := first_segment(tail)
    if list.len(segs) < 2 {
      None
    } else { if ver == versions.v221() {
      None
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

# Body-shape gate. POST/PUT/PATCH with a non-empty, non-JSON body
# returns 2001 — the same gate the fake CPO ships, so both peers
# emit the spec-required negative shape.
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

# ---- URL → (module, path_params) --------------------------------

type RouteHit = { module :: Str, params :: Map[Str, Str] }

fn map_url_to_module(path :: Str) -> Option[RouteHit] {
  if path == "/ocpi/versions" {
    Some({ module: mid.versions(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/" or path == "/ocpi/2.2.1" {
    Some({ module: "version_detail", params: map.new() })
  } else { if path == "/ocpi/2.2.1/tariffs" {
    Some({ module: mid.tariffs(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/cdrs" {
    Some({ module: mid.cdrs(), params: map.new() })
  } else { if path == "/ocpi/2.2.1/tokens" {
    Some({ module: mid.tokens(), params: map.new() })
  } else { if is_authorize_path(path) {
    let uid := extract_token_uid(path)
    Some({
      module: "token_authorize",
      params: map.set(map.new(), "token_uid", uid),
    })
  } else {
    None
  } } } } } }
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

fn main() -> [net, io, time, concurrent] Nil {
  let _ := io.print("eMSP v2.2.1  http://localhost:9101/ocpi/versions")
  let actor := conc.spawn({ last: None }, cb_handler)
  net.serve_fn(9101,
    fn (req :: Request) -> [time, concurrent] Response { handle(actor, req) })
}
