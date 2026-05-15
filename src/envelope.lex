# lex-ocpi — OCPI response envelope
#
# Every OCPI response is wrapped in a fixed-shape JSON envelope:
#
#   { "data":           <payload | [payload] | string | null>,
#     "status_code":    <four-digit OCPI status code>,
#     "status_message": "<optional human-readable detail>",
#     "timestamp":      "<ISO-8601 generation time>" }
#
# The envelope is identical across every module and every version
# (2.1.1 / 2.2.1 / 2.3.0). This module is the only place the wire
# shape lives — module handlers return either a payload or an
# `OcpiError`, and the routing layer wraps the result.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.1 (Response Object)
#   OCPI 2.3.0 — Part I §4.1
#
# Effects: none. Encode / decode are pure folds over JSON.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "lex-schema/json_value" as jv

# ---- Response envelope datatype ----------------------------------
#
# The envelope's `data` field is left as a raw `jv.Json` so callers
# can carry a single object, a list, a string, or null without
# committing to a single shape at the type level. Module-specific
# schemas validate the inner shape; the envelope is wire-format only.

type OcpiResponse = {
  data           :: jv.Json,
  status_code    :: Int,
  status_message :: Str,
  timestamp      :: Str,
}

# ---- Constructors ------------------------------------------------
#
# `ok` / `ok_list` / `fail` cover the three call-site shapes a
# handler typically returns. `at` lets callers thread a custom
# timestamp (for replayable test fixtures); the effectful path
# in `route_io` calls `at` after stamping with `time.now_str()`.

fn ok(data :: jv.Json, timestamp :: Str) -> OcpiResponse {
  at(data, 1000, "", timestamp)
}

fn ok_list(items :: List[jv.Json], timestamp :: Str) -> OcpiResponse {
  at(JList(items), 1000, "", timestamp)
}

fn ok_empty(timestamp :: Str) -> OcpiResponse {
  at(JNull, 1000, "", timestamp)
}

fn fail(status_code :: Int, status_message :: Str, timestamp :: Str) -> OcpiResponse {
  at(JNull, status_code, status_message, timestamp)
}

fn fail_with_data(
  status_code    :: Int,
  status_message :: Str,
  data           :: jv.Json,
  timestamp      :: Str
) -> OcpiResponse {
  at(data, status_code, status_message, timestamp)
}

fn at(
  data           :: jv.Json,
  status_code    :: Int,
  status_message :: Str,
  timestamp      :: Str
) -> OcpiResponse {
  {
    data:           data,
    status_code:    status_code,
    status_message: status_message,
    timestamp:      timestamp,
  }
}

# ---- Encoding ----------------------------------------------------
#
# Serialise an `OcpiResponse` to the wire JSON. `status_message` is
# omitted when empty per the OCPI spec (Part I §4.1.2 — "may be
# omitted when status_code indicates success").

fn to_json(r :: OcpiResponse) -> jv.Json {
  let base := [
    ("data",        r.data),
    ("status_code", JInt(r.status_code)),
  ]
  let with_msg := if str.is_empty(r.status_message) {
    base
  } else {
    list.concat(base, [("status_message", JStr(r.status_message))])
  }
  JObj(list.concat(with_msg, [("timestamp", JStr(r.timestamp))]))
}

fn encode(r :: OcpiResponse) -> Str {
  jv.stringify(to_json(r))
}

# ---- Decoding ----------------------------------------------------
#
# Parse an inbound OCPI response. Useful on the client side (eMSP
# receiving a CPO response, or vice versa). Missing / malformed
# fields surface as an `EnvelopeError`, never a VM panic.

type EnvelopeError = { message :: Str }

fn envelope_err(message :: Str) -> EnvelopeError {
  { message: message }
}

fn from_json(j :: jv.Json) -> Result[OcpiResponse, EnvelopeError] {
  match jv.as_obj(j) {
    None => Err(envelope_err("envelope must be a JSON object")),
    Some(_) => read_fields(j),
  }
}

fn read_fields(j :: jv.Json) -> Result[OcpiResponse, EnvelopeError] {
  let data_o := jv.get_field(j, "data")
  let code_o := jv.get_field(j, "status_code")
  let ts_o   := jv.get_field(j, "timestamp")
  match (code_o, ts_o) {
    (Some(code_j), Some(ts_j)) => match jv.as_int(code_j) {
      None => Err(envelope_err("status_code must be a number")),
      Some(code) => match jv.as_str(ts_j) {
        None => Err(envelope_err("timestamp must be a string")),
        Some(ts) => Ok(at(
          match data_o { None => JNull, Some(d) => d },
          code,
          read_status_message(j),
          ts)),
      },
    },
    _ => Err(envelope_err("envelope missing status_code or timestamp")),
  }
}

fn read_status_message(j :: jv.Json) -> Str {
  match jv.get_field(j, "status_message") {
    None    => "",
    Some(m) => match jv.as_str(m) {
      None    => "",
      Some(s) => s,
    },
  }
}

fn parse(raw :: Str) -> Result[OcpiResponse, EnvelopeError] {
  match jv.parse(raw) {
    Err(p) => Err(envelope_err(str.concat("invalid JSON: ", p.message))),
    Ok(j)  => from_json(j),
  }
}

# ---- Predicates --------------------------------------------------

fn is_success(r :: OcpiResponse) -> Bool {
  r.status_code >= 1000 and r.status_code < 2000
}

fn is_client_error(r :: OcpiResponse) -> Bool {
  r.status_code >= 2000 and r.status_code < 3000
}

fn is_server_error(r :: OcpiResponse) -> Bool {
  r.status_code >= 3000 and r.status_code < 4000
}

fn is_hub_error(r :: OcpiResponse) -> Bool {
  r.status_code >= 4000 and r.status_code < 5000
}
