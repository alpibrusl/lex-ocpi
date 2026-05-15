# lex-ocpi — schema export demo
#
# Same `ModelSchema` value, four downstream targets:
#   1. JSON Schema 2020-12  (browser-side validation / docs)
#   2. OpenAPI 3.1 component (route docs / SwaggerUI)
#   3. TypeScript interface  (eMSP / CPO frontend consumers)
#   4. Pydantic v2 class     (Python OCPI clients)
#
# The point is that the same ModelSchema drives runtime validation
# AND every codegen target — agents emitting OCPI integrations in
# non-Lex stacks consume the export of whichever target matches.
#
# Run:
#   lex run --allow-effects io examples/export_schemas.lex main
#
# Effects: `[io]` for printing the output.

import "std.io"   as io
import "std.str"  as str

import "lex-schema/json_value" as jv
import "lex-schema/schema"     as s
import "lex-schema/sdk"        as sdk

import "../src/v221/tokens"  as tokens
import "../src/v221/sessions" as sessions
import "../src/v230/payments" as payments

# ---- Headers ----------------------------------------------------

fn section(title :: Str) -> [io] Nil {
  let _ := io.print("")
  let _ := io.print(str.concat("── ", str.concat(title, " ──")))
  io.print("")
}

# ---- Per-target export -----------------------------------------

fn dump_target(schema :: s.ModelSchema, name :: Str) -> [io] Nil {
  let _ := section(str.concat(name, "  →  JSON Schema 2020-12"))
  let _ := io.print(jv.stringify(s.to_json_schema(schema)))

  let _ := section(str.concat(name, "  →  OpenAPI 3.1 component"))
  let _ := io.print(jv.stringify(s.to_openapi_schema(schema)))

  let _ := section(str.concat(name, "  →  TypeScript interface"))
  let _ := io.print(sdk.to_typescript(schema))

  let _ := section(str.concat(name, "  →  Pydantic v2 class"))
  io.print(sdk.to_python(schema))
}

# ---- Entry point ------------------------------------------------

fn main() -> [io] Nil {
  let _ := io.print("============================================")
  let _ := io.print("  lex-ocpi schema export — Token (OCPI 2.2.1)")
  let _ := io.print("============================================")
  let _ := dump_target(tokens.token_schema(), "OCPI 2.2.1 — Token")

  let _ := io.print("")
  let _ := io.print("============================================")
  let _ := io.print("  lex-ocpi schema export — Session (OCPI 2.2.1)")
  let _ := io.print("============================================")
  let _ := dump_target(sessions.session_schema(), "OCPI 2.2.1 — Session")

  let _ := io.print("")
  let _ := io.print("============================================")
  let _ := io.print("  lex-ocpi schema export — Payment (OCPI 2.3.0)")
  let _ := io.print("============================================")
  let _ := dump_target(payments.payment_schema(), "OCPI 2.3.0 — Payment")

  let _ := io.print("")
  io.print("done — feed any of the above into your downstream consumer")
}
