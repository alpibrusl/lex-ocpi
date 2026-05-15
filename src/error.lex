# lex-ocpi — OCPI error helpers
#
# Module handlers return either a payload or an `OcpiError`. The
# routing layer wraps the result in an `OcpiResponse` envelope (see
# `envelope.lex`), so handlers never touch the wire shape directly.
#
# `OcpiError` carries the four-digit status code, the human-readable
# message, and optional structured detail (for schema-validation
# failures, the per-field violation list).
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.1 (Response Object — status_code)
#   OCPI 2.2.1 — Part I §6 (Status codes)
#
# Effects: none.

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "./status" as status

# ---- Error datatype ----------------------------------------------
#
# Carrying `detail` as a `Json` means callers can attach arbitrary
# structured context (which field failed validation, the OCPI
# party that timed out, the unsupported version that was requested,
# …) without committing to a specific shape.

type OcpiError = {
  code    :: Int,
  message :: Str,
  detail  :: jv.Json,
}

fn err(code :: Int, message :: Str) -> OcpiError {
  { code: code, message: message, detail: JNull }
}

fn err_with(code :: Int, message :: Str, detail :: jv.Json) -> OcpiError {
  { code: code, message: message, detail: detail }
}

# ---- Common helpers ----------------------------------------------
#
# One constructor per status code in the spec's 2xxx / 3xxx ranges.
# Handlers reach for these rather than building the raw `{code,
# message, detail}` record at the call site.

fn invalid_parameters(description :: Str) -> OcpiError {
  err(status.invalid_or_missing_parameters(), description)
}

fn not_enough_information(description :: Str) -> OcpiError {
  err(status.not_enough_information(), description)
}

fn unknown_location(location_id :: Str) -> OcpiError {
  err_with(status.unknown_location(),
    str.concat("Unknown Location: ", location_id),
    JObj([("location_id", JStr(location_id))]))
}

fn unknown_token(token_uid :: Str) -> OcpiError {
  err_with(status.unknown_token(),
    str.concat("Unknown Token: ", token_uid),
    JObj([("uid", JStr(token_uid))]))
}

fn server_error(description :: Str) -> OcpiError {
  err(status.server_error(), description)
}

fn unsupported_version(version :: Str) -> OcpiError {
  err_with(status.unsupported_version(),
    str.concat("Unsupported version: ", version),
    JObj([("version", JStr(version))]))
}

fn unable_to_use_api(description :: Str) -> OcpiError {
  err(status.unable_to_use_api(), description)
}

# ---- Schema-error adapter ----------------------------------------
#
# Convert a `lex-schema` validation failure into an OCPI client
# error. The resulting envelope returns status `2001` with the
# full list of failing fields in `data` — a UI rendering the
# response can highlight every failing field in a single pass.

fn from_schema_errors(
  es :: List[{ path :: Str, code :: Str, message :: Str }]
) -> OcpiError {
  let entries := list.map(es,
    fn (e :: { path :: Str, code :: Str, message :: Str }) -> jv.Json {
      JObj([
        ("path",    JStr(e.path)),
        ("code",    JStr(e.code)),
        ("message", JStr(e.message)),
      ])
    })
  err_with(status.invalid_or_missing_parameters(),
    "request payload failed schema validation",
    JObj([("violations", JList(entries))]))
}
