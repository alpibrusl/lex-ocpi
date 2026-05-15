# lex-ocpi — handler registry + dispatch
#
# OCPI is HTTP-based (unlike OCPP's WebSocket framing), but it
# inherits the same shape we use in lex-ocpp: a per-action registry
# of pure handlers, each guarded by an optional payload validator.
# Routes are keyed by `(method, module, interface_role)` rather than
# a single action name — OCPI is REST, so the HTTP verb matters.
#
# Pure-core design (matches lex-ocpp / lex-web):
#
#   handler ::  (OcpiRequest) -> HandlerResult
#   dispatch :: (Registry, OcpiRequest) -> OcpiResponse
#
# The dispatcher takes an inbound request, validates the payload
# (if a validator is registered), invokes the handler, and wraps the
# result in an OCPI envelope ready for the transport to ship.
#
# Effects: none. Layer a `[net, io, time]` adapter on top via
# lex-web's router to drive the dispatcher.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "./envelope" as env
import "./error"    as oe
import "./headers"  as headers
import "./status"   as status

# ---- Method constants --------------------------------------------
#
# OCPI uses the standard HTTP verb set. Constants here keep call
# sites typo-proof.

fn get()    -> Str { "GET" }
fn post()   -> Str { "POST" }
fn put()    -> Str { "PUT" }
fn patch()  -> Str { "PATCH" }
fn delete() -> Str { "DELETE" }

# ---- OcpiRequest -------------------------------------------------
#
# The parsed view of an inbound OCPI HTTP request. Path parameters
# (country_code, party_id, location_id, etc.) are exposed as a
# Map[Str, Str] populated by the router from the route template.

type OcpiRequest = {
  method      :: Str,
  module      :: Str,
  path        :: Str,
  path_params :: Map[Str, Str],
  query       :: Map[Str, Str],
  headers     :: headers.OcpiHeaders,
  body        :: jv.Json,
}

fn request(
  method      :: Str,
  module      :: Str,
  path        :: Str,
  path_params :: Map[Str, Str],
  query       :: Map[Str, Str],
  hdrs        :: headers.OcpiHeaders,
  body        :: jv.Json
) -> OcpiRequest {
  {
    method:      method,
    module:      module,
    path:        path,
    path_params: path_params,
    query:       query,
    headers:     hdrs,
    body:        body,
  }
}

# ---- Handler types -----------------------------------------------

type HandlerResult =
    HOk(jv.Json)
  | HOkList(List[jv.Json])
  | HOkEmpty
  | HErr(oe.OcpiError)

# Pure handler signature. Body payloads, path params, query, and
# the OCPI headers are all available on the request.
type Handler = (OcpiRequest) -> HandlerResult

# Validator runs against the parsed JSON body. Same shape as
# `lex-schema/validator.validate`; any schema or hand-rolled
# combinator that fits matches.
type Validator = (jv.Json) -> Result[jv.Json, List[e.Error]]

# Fallback for inbound requests that don't match any registered
# route. Default returns `2000` — `not implemented`.
type Fallback = (OcpiRequest) -> HandlerResult

# ---- Registry datatype -------------------------------------------
#
# A route entry pins a handler to one HTTP `(method, module)` pair.
# The module string matches the OCPI module identifier (`"locations"`,
# `"sessions"`, `"credentials"`, …) so a handler is registered once
# regardless of how it's mounted on the wire.

type RouteEntry = {
  method    :: Str,
  module    :: Str,
  validator :: Option[(jv.Json) -> Result[jv.Json, List[e.Error]]],
  handler   :: (OcpiRequest) -> HandlerResult,
}

type Registry = {
  routes     :: List[RouteEntry],
  on_unknown :: (OcpiRequest) -> HandlerResult,
}

# ---- Registry construction ---------------------------------------

fn new() -> Registry {
  { routes: [], on_unknown: default_unknown }
}

fn default_unknown(req :: OcpiRequest) -> HandlerResult {
  HErr(oe.err(status.client_error(),
    str.concat("no handler for ",
      str.concat(req.method, str.concat(" ", req.module)))))
}

fn with_unknown(reg :: Registry, fb :: Fallback) -> Registry {
  { routes: reg.routes, on_unknown: fb }
}

# Register a handler with no body schema. Useful for GET endpoints
# that have no inbound payload.
fn handler(
  reg    :: Registry,
  method :: Str,
  module :: Str,
  h      :: Handler
) -> Registry {
  add_entry(reg, {
    method: method, module: module, validator: None, handler: h,
  })
}

# Register a handler that validates the inbound body. Schema
# failures surface as `2001 — Invalid or missing parameters` with
# the full violation list in `data`.
fn handler_with_schema(
  reg       :: Registry,
  method    :: Str,
  module    :: Str,
  validator :: Validator,
  h         :: Handler
) -> Registry {
  add_entry(reg, {
    method: method, module: module, validator: Some(validator), handler: h,
  })
}

fn add_entry(reg :: Registry, entry :: RouteEntry) -> Registry {
  { routes: list.concat(reg.routes, [entry]),
    on_unknown: reg.on_unknown }
}

# ---- Lookup ------------------------------------------------------

fn find(reg :: Registry, method :: Str, module :: Str) -> Option[RouteEntry] {
  list.fold(reg.routes, None,
    fn (acc :: Option[RouteEntry], entry :: RouteEntry) -> Option[RouteEntry] {
      match acc {
        Some(_) => acc,
        None    => if entry.method == method and entry.module == module {
                     Some(entry)
                   } else {
                     None
                   },
      }
    })
}

fn routes(reg :: Registry) -> List[(Str, Str)] {
  list.map(reg.routes,
    fn (entry :: RouteEntry) -> (Str, Str) { (entry.method, entry.module) })
}

# ---- Dispatch ----------------------------------------------------
#
# `dispatch` turns an inbound request into an OCPI response. The
# response envelope is built using the caller-supplied timestamp —
# pure code, callable from tests. The effectful adapter (in
# `route_io.lex`, future work) supplies `time.now_str()`.

fn dispatch(reg :: Registry, req :: OcpiRequest, timestamp :: Str) -> env.OcpiResponse {
  match find(reg, req.method, req.module) {
    None        => response_from_handler(reg.on_unknown(req), timestamp),
    Some(entry) => run_entry(entry, req, timestamp),
  }
}

fn run_entry(
  entry     :: RouteEntry,
  req       :: OcpiRequest,
  timestamp :: Str
) -> env.OcpiResponse {
  match entry.validator {
    None     => response_from_handler((entry.handler)(req), timestamp),
    Some(vf) => match vf(req.body) {
      Err(es) => response_from_handler(
                   HErr(oe.from_schema_errors(es)), timestamp),
      Ok(normalized) => {
        let r2 := request(req.method, req.module, req.path,
                    req.path_params, req.query, req.headers, normalized)
        response_from_handler((entry.handler)(r2), timestamp)
      },
    },
  }
}

fn response_from_handler(hr :: HandlerResult, timestamp :: Str) -> env.OcpiResponse {
  match hr {
    HOk(payload)   => env.ok(payload, timestamp),
    HOkList(items) => env.ok_list(items, timestamp),
    HOkEmpty       => env.ok_empty(timestamp),
    HErr(oerr)     => env.fail_with_data(oerr.code, oerr.message,
                        oerr.detail, timestamp),
  }
}

# ---- Convenience builders for HandlerResult ----------------------

fn ok(payload :: jv.Json) -> HandlerResult { HOk(payload) }

fn ok_list(items :: List[jv.Json]) -> HandlerResult { HOkList(items) }

fn ok_empty() -> HandlerResult { HOkEmpty }

fn fail(oerr :: oe.OcpiError) -> HandlerResult { HErr(oerr) }

fn fail_with(code :: Int, message :: Str) -> HandlerResult {
  HErr(oe.err(code, message))
}
