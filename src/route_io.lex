# lex-ocpi — effectful handler registry + dispatch
#
# Same shape as `route.lex` but with handlers carrying an `[io, time,
# sql]` upper bound. Real OCPI CPOs persist Locations / Sessions /
# CDRs via lex-orm, log via `io.print`, and stamp `last_updated`
# timestamps via `time.now_str`. The pure registry can't host those;
# this module is the effectful sibling.
#
# Caveat: handlers declaring effects outside `[io, time, sql]` (e.g.
# `[fs_read]`, `[net]`, `[random]`) don't fit. Wrap your own
# dispatcher on top of `route.dispatch` if you need a different
# effect set — Lex 0.9.x has no effect polymorphism on function
# pointers in records (see lex-lang notes in lex-ocpp's CHANGELOG).
#
# Spec references: same as `route.lex`.
#
# Effects: handlers run inside `[io, time, sql]` upper bound.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "./envelope" as env
import "./error"    as oe
import "./route"    as route
import "./status"   as status

# ---- Handler types -----------------------------------------------

type IoHandler = (route.OcpiRequest) -> [io, time, sql] route.HandlerResult
type IoFallback = (route.OcpiRequest) -> [io, time, sql] route.HandlerResult

# ---- Registry datatype -------------------------------------------

type IoRouteEntry = {
  method    :: Str,
  module    :: Str,
  validator :: Option[(jv.Json) -> Result[jv.Json, List[e.Error]]],
  handler   :: (route.OcpiRequest) -> [io, time, sql] route.HandlerResult,
}

type IoRegistry = {
  routes     :: List[IoRouteEntry],
  on_unknown :: (route.OcpiRequest) -> [io, time, sql] route.HandlerResult,
}

# ---- Registry construction ---------------------------------------

fn new() -> IoRegistry {
  { routes: [], on_unknown: default_unknown }
}

fn default_unknown(req :: route.OcpiRequest) -> [io, time, sql] route.HandlerResult {
  route.fail(oe.err(status.client_error(),
    str.concat("no handler for ",
      str.concat(req.method, str.concat(" ", req.module)))))
}

fn with_unknown(reg :: IoRegistry, fb :: IoFallback) -> IoRegistry {
  { routes: reg.routes, on_unknown: fb }
}

fn handler(
  reg    :: IoRegistry,
  method :: Str,
  module :: Str,
  h      :: IoHandler
) -> IoRegistry {
  add_entry(reg, {
    method: method, module: module, validator: None, handler: h,
  })
}

fn handler_with_schema(
  reg       :: IoRegistry,
  method    :: Str,
  module    :: Str,
  validator :: route.Validator,
  h         :: IoHandler
) -> IoRegistry {
  add_entry(reg, {
    method: method, module: module,
    validator: Some(validator), handler: h,
  })
}

fn add_entry(reg :: IoRegistry, entry :: IoRouteEntry) -> IoRegistry {
  { routes: list.concat(reg.routes, [entry]),
    on_unknown: reg.on_unknown }
}

# ---- Lookup ------------------------------------------------------

fn find(reg :: IoRegistry, method :: Str, module :: Str) -> Option[IoRouteEntry] {
  list.fold(reg.routes, None,
    fn (acc :: Option[IoRouteEntry], entry :: IoRouteEntry) -> Option[IoRouteEntry] {
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

# ---- Dispatch ----------------------------------------------------

fn dispatch(
  reg       :: IoRegistry,
  req       :: route.OcpiRequest,
  timestamp :: Str
) -> [io, time, sql] env.OcpiResponse {
  match find(reg, req.method, req.module) {
    None        => response_from_handler(reg.on_unknown(req), timestamp),
    Some(entry) => run_entry(entry, req, timestamp),
  }
}

fn run_entry(
  entry     :: IoRouteEntry,
  req       :: route.OcpiRequest,
  timestamp :: Str
) -> [io, time, sql] env.OcpiResponse {
  match entry.validator {
    None     => response_from_handler((entry.handler)(req), timestamp),
    Some(vf) => match vf(req.body) {
      Err(es) => response_from_handler(
                   route.fail(oe.from_schema_errors(es)), timestamp),
      Ok(normalized) => {
        let r2 := route.request(req.method, req.module, req.path,
                    req.path_params, req.query, req.headers, normalized)
        response_from_handler((entry.handler)(r2), timestamp)
      },
    },
  }
}

fn response_from_handler(
  hr        :: route.HandlerResult,
  timestamp :: Str
) -> env.OcpiResponse {
  match hr {
    HOk(payload)   => env.ok(payload, timestamp),
    HOkList(items) => env.ok_list(items, timestamp),
    HOkEmpty       => env.ok_empty(timestamp),
    HErr(oerr)     => env.fail_with_data(oerr.code, oerr.message,
                        oerr.detail, timestamp),
  }
}
