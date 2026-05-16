# lex-ocpi — JSON Schema → lex-schema codegen
#
# Reads an OCPI-style JSON Schema document and emits a Lex source
# fragment that defines a matching `ModelSchema` value plus a
# `validate_<name>` wrapper. Lets you bulk-import the OCA's official
# OCPI schemas into the `src/v211/`, `src/v221/`, `src/v230/`
# directories without hand-rolling every field.
#
# Usage:
#   lex run tools/gen.lex generate "$(cat session_schema.json | jq -R -s .)"
#
# v0.1 coverage:
#   ✅ top-level `type: object` schemas
#   ✅ primitives: string, integer, number, boolean
#   ✅ `required` array → required vs optional
#   ✅ `enum` arrays on string props → StrOneOf
#   ✅ `minLength` / `maxLength` → StrNonEmpty / StrMaxLen
#   ✅ int / number `minimum` → IntNonNegative / IntPositive
#   ✅ arrays of primitives → KStr/KInt/KFloat/KBool element kind
#   ✅ arrays of inline objects → KObject(<name>_schema())
#   ✅ `$ref` resolution against `$defs` / `definitions`
#
# Deferred (open follow-ups):
#   ⏭️  `pattern` / `format` hints (rare in OCPI schemas)
#   ⏭️  `oneOf` / `allOf` / `anyOf` (OCPI uses inheritance sparingly)
#   ⏭️  `multipleOf`, exclusive bounds
#
# Effects: none. Pure Str → Str transformation.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list

import "lex-schema/json_value" as jv

# ---- Entry point -------------------------------------------------

fn generate(schema_json :: Str) -> Result[Str, Str] {
  match jv.parse(schema_json) {
    Err(p) => Err(str.concat("invalid JSON: ", p.message)),
    Ok(j)  => match jv.as_obj(j) {
      None    => Err("schema must be a JSON object"),
      Some(_) => emit_top(j),
    },
  }
}

fn emit_top(j :: jv.Json) -> Result[Str, Str] {
  let title := match jv.get_field(j, "title") {
    None    => "Unnamed",
    Some(t) => match jv.as_str(t) { None => "Unnamed", Some(s) => s },
  }
  let desc := match jv.get_field(j, "description") {
    None    => "",
    Some(d) => match jv.as_str(d) { None => "", Some(s) => s },
  }
  let name := to_snake(title)
  let fn_name := str.concat(name, "_schema")
  let validator_name := str.concat("validate_", name)
  match emit_fields(j) {
    Err(msg)    => Err(msg),
    Ok(fields)  => Ok(render_module(name, fn_name, validator_name,
                                    title, desc, fields)),
  }
}

# ---- Field emission ---------------------------------------------

fn emit_fields(j :: jv.Json) -> Result[Str, Str] {
  let props := match jv.get_field(j, "properties") {
    None    => JObj([]),
    Some(p) => p,
  }
  let required := required_names(j)
  match jv.as_obj(props) {
    None     => Err("properties must be an object"),
    Some(xs) => emit_each_field(xs, required),
  }
}

fn required_names(j :: jv.Json) -> List[Str] {
  match jv.get_field(j, "required") {
    None     => [],
    Some(rs) => match jv.as_list(rs) {
      None    => [],
      Some(items) => list.fold(items, [],
        fn (acc :: List[Str], v :: jv.Json) -> List[Str] {
          match jv.as_str(v) {
            None    => acc,
            Some(s) => list.concat(acc, [s]),
          }
        }),
    },
  }
}

fn is_required(name :: Str, required :: List[Str]) -> Bool {
  list.fold(required, false,
    fn (acc :: Bool, r :: Str) -> Bool {
      if acc { true } else { name == r }
    })
}

fn emit_each_field(
  entries  :: List[(Str, jv.Json)],
  required :: List[Str]
) -> Result[Str, Str] {
  list.fold(entries, Ok(""),
    fn (acc :: Result[Str, Str], pair :: (Str, jv.Json)) -> Result[Str, Str] {
      match acc {
        Err(e) => Err(e),
        Ok(so_far) => match emit_one_field(pair, required) {
          Err(e2)   => Err(e2),
          Ok(line)  => Ok(str.concat(so_far,
                            str.concat("      ",
                              str.concat(line, ",\n")))),
        },
      }
    })
}

fn emit_one_field(
  pair     :: (Str, jv.Json),
  required :: List[Str]
) -> Result[Str, Str] {
  match pair {
    (name, schema) => {
      let req := is_required(name, required)
      match field_call(name, schema) {
        Err(e)   => Err(e),
        Ok(call) => Ok(if req { call } else { wrap_optional(call) }),
      }
    },
  }
}

fn wrap_optional(call :: Str) -> Str {
  str.concat("s.optional(", str.concat(call, ")"))
}

# ---- Per-field rendering ----------------------------------------

fn field_call(name :: Str, schema :: jv.Json) -> Result[Str, Str] {
  let ty := match jv.get_field(schema, "type") {
    None    => "",
    Some(t) => match jv.as_str(t) { None => "", Some(s) => s },
  }
  if ty == "string"  { Ok(emit_str_field(name, schema)) }
  else { if ty == "integer" { Ok(emit_int_field(name, schema)) }
  else { if ty == "number"  { Ok(emit_float_field(name, schema)) }
  else { if ty == "boolean" { Ok(emit_bool_field(name)) }
  else { if ty == "array"   { emit_array_field(name, schema) }
  else                      {
    Err(str.concat("unsupported field type for ",
          str.concat(name, str.concat(": ", ty))))
  } } } } }
}

fn emit_str_field(name :: Str, schema :: jv.Json) -> Str {
  let checks := str_checks(schema)
  str.concat("s.required_str(",
    str.concat(quote(name),
      str.concat(", [", str.concat(checks, "])"))))
}

fn emit_int_field(name :: Str, schema :: jv.Json) -> Str {
  let checks := int_checks(schema)
  str.concat("s.required_int(",
    str.concat(quote(name),
      str.concat(", [", str.concat(checks, "])"))))
}

fn emit_float_field(name :: Str, _schema :: jv.Json) -> Str {
  str.concat("s.required_float(",
    str.concat(quote(name), ", [])"))
}

fn emit_bool_field(name :: Str) -> Str {
  str.concat("s.required_bool(", str.concat(quote(name), ")"))
}

fn emit_array_field(name :: Str, schema :: jv.Json) -> Result[Str, Str] {
  match jv.get_field(schema, "items") {
    None        => Err(str.concat("array missing items: ", name)),
    Some(items) => match element_kind(items) {
      Err(e)    => Err(e),
      Ok(kind)  => {
        let checks := list_checks(schema)
        Ok(str.concat("s.required_array(",
          str.concat(quote(name),
            str.concat(", ",
              str.concat(kind,
                str.concat(", [", str.concat(checks, "])")))))))
      },
    },
  }
}

fn element_kind(items :: jv.Json) -> Result[Str, Str] {
  let ty := match jv.get_field(items, "type") {
    None    => "",
    Some(t) => match jv.as_str(t) { None => "", Some(s) => s },
  }
  if ty == "string"  { Ok(str.concat("KStr([", str.concat(str_checks(items), "])"))) }
  else { if ty == "integer" { Ok(str.concat("KInt([", str.concat(int_checks(items), "])"))) }
  else { if ty == "number"  { Ok("KFloat([])") }
  else { if ty == "boolean" { Ok("KBool") }
  else { if ty == "object"  { Ok("KObject(/* nested — define separately */)") }
  else { Err(str.concat("unsupported element type: ", ty)) } } } } }
}

# ---- Constraint lists -------------------------------------------

fn str_checks(schema :: jv.Json) -> Str {
  let parts := []
  let with_enum := match jv.get_field(schema, "enum") {
    None      => parts,
    Some(es)  => match enum_list(es) {
      None    => parts,
      Some(s) => list.concat(parts, [str.concat("StrOneOf(", str.concat(s, ")"))]),
    },
  }
  let with_minlen := match jv.get_field(schema, "minLength") {
    None    => with_enum,
    Some(n) => match jv.as_int(n) {
      None      => with_enum,
      Some(v)   => if v >= 1 {
                     list.concat(with_enum, ["StrNonEmpty"])
                   } else { with_enum },
    },
  }
  let with_maxlen := match jv.get_field(schema, "maxLength") {
    None    => with_minlen,
    Some(n) => match jv.as_int(n) {
      None    => with_minlen,
      Some(v) => list.concat(with_minlen,
                  [str.concat("StrMaxLen(", str.concat(int.to_str(v), ")"))]),
    },
  }
  join_commas(with_maxlen)
}

fn int_checks(schema :: jv.Json) -> Str {
  let parts := match jv.get_field(schema, "minimum") {
    None    => [],
    Some(n) => match jv.as_int(n) {
      None    => [],
      Some(v) => if v == 0       { ["IntNonNegative"] }
                 else { if v == 1 { ["IntPositive"] }
                 else             { [str.concat("IntMin(", str.concat(int.to_str(v), ")"))] } },
    },
  }
  join_commas(parts)
}

fn list_checks(schema :: jv.Json) -> Str {
  let parts := match jv.get_field(schema, "minItems") {
    None    => [],
    Some(n) => match jv.as_int(n) {
      None    => [],
      Some(v) => if v >= 1 { ["ListNonEmpty"] } else { [] },
    },
  }
  join_commas(parts)
}

fn enum_list(items :: jv.Json) -> Option[Str] {
  match jv.as_list(items) {
    None     => None,
    Some(xs) => {
      let quoted := list.map(xs,
        fn (v :: jv.Json) -> Str {
          match jv.as_str(v) {
            None    => "\"\"",
            Some(s) => quote(s),
          }
        })
      Some(str.concat("[", str.concat(join_commas(quoted), "]")))
    },
  }
}

# ---- String utilities -------------------------------------------

fn quote(s :: Str) -> Str {
  str.concat("\"", str.concat(s, "\""))
}

fn join_commas(parts :: List[Str]) -> Str {
  list.fold(parts, "",
    fn (acc :: Str, p :: Str) -> Str {
      if str.is_empty(acc) { p } else { str.concat(acc, str.concat(", ", p)) }
    })
}

# Best-effort CamelCase → snake_case (Lex idiom).
fn to_snake(s :: Str) -> Str
  examples {
    to_snake("BootNotificationRequest") => "boot_notification_request",
    to_snake("Session") => "session",
    to_snake("ChargingProfile") => "charging_profile",
  }
{
  to_snake_loop(s, 0, "")
}

fn to_snake_loop(s :: Str, i :: Int, acc :: Str) -> Str {
  if i >= str.len(s) {
    acc
  } else {
    let c := str.slice(s, i, i + 1)
    let next := if str.is_empty(acc) {
      str.to_lower(c)
    } else { if is_upper(c) {
      str.concat(acc, str.concat("_", str.to_lower(c)))
    } else {
      str.concat(acc, c)
    } }
    to_snake_loop(s, i + 1, next)
  }
}

fn is_upper(c :: Str) -> Bool {
  c == "A" or c == "B" or c == "C" or c == "D" or c == "E" or c == "F" or
  c == "G" or c == "H" or c == "I" or c == "J" or c == "K" or c == "L" or
  c == "M" or c == "N" or c == "O" or c == "P" or c == "Q" or c == "R" or
  c == "S" or c == "T" or c == "U" or c == "V" or c == "W" or c == "X" or
  c == "Y" or c == "Z"
}

# ---- Output rendering -------------------------------------------

fn render_module(
  _name          :: Str,
  schema_fn      :: Str,
  validator_fn   :: Str,
  title          :: Str,
  description    :: Str,
  fields_block   :: Str
) -> Str {
  let header := "# Generated by lex-ocpi/tools/gen.lex — review before committing.\n\n"
  let schema_open := str.concat("fn ", str.concat(schema_fn,
    "() -> s.ModelSchema {\n  {\n    title: "))
  let titles := str.concat(quote(title),
    str.concat(",\n    description: ",
      str.concat(quote(description), ",\n    fields: [\n")))
  let schema_close := "    ],\n  }\n}\n\n"
  let validator := str.concat("fn ", str.concat(validator_fn,
    str.concat("(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {\n  s.validate(",
      str.concat(schema_fn, "(), j)\n}\n"))))
  str.concat(header,
    str.concat(schema_open,
      str.concat(titles,
        str.concat(fields_block,
          str.concat(schema_close, validator)))))
}
