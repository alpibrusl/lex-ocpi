# lex-ocpi — JSON Schema → ModelSchema codegen tests

import "std.str"  as str
import "std.list" as list

import "../tools/gen" as gen

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_contains(s :: Str, needle :: Str, label :: Str) -> Result[Unit, Str] {
  if str.contains(s, needle) { pass() } else {
    fail(str.concat(label, str.concat(": missing '", str.concat(needle, "'"))))
  }
}

# ---- Minimal schema: title + one required string ----------------

fn test_minimal_schema() -> Result[Unit, Str] {
  let input := "{\"title\":\"Heartbeat\",\"type\":\"object\",\"required\":[\"timestamp\"],\"properties\":{\"timestamp\":{\"type\":\"string\"}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "fn heartbeat_schema",
      "schema fn name"),
  }
}

# ---- Required vs optional ---------------------------------------

fn test_required_vs_optional() -> Result[Unit, Str] {
  let input := "{\"title\":\"X\",\"type\":\"object\",\"required\":[\"a\"],\"properties\":{\"a\":{\"type\":\"string\"},\"b\":{\"type\":\"string\"}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => if str.contains(out, "s.required_str(\"a\"")
                  and str.contains(out, "s.optional(s.required_str(\"b\"") {
      pass()
    } else {
      fail("optional wrapper missing on non-required field")
    },
  }
}

# ---- Enum → StrOneOf --------------------------------------------

fn test_enum() -> Result[Unit, Str] {
  let input := "{\"title\":\"S\",\"type\":\"object\",\"required\":[\"k\"],\"properties\":{\"k\":{\"type\":\"string\",\"enum\":[\"A\",\"B\"]}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "StrOneOf([\"A\", \"B\"])", "enum"),
  }
}

# ---- String length constraints ----------------------------------

fn test_max_len() -> Result[Unit, Str] {
  let input := "{\"title\":\"S\",\"type\":\"object\",\"required\":[\"k\"],\"properties\":{\"k\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":20}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => if str.contains(out, "StrNonEmpty") and str.contains(out, "StrMaxLen(20)") {
      pass()
    } else {
      fail("min/max length constraints missing")
    },
  }
}

# ---- Int minimum ------------------------------------------------

fn test_int_min_zero() -> Result[Unit, Str] {
  let input := "{\"title\":\"S\",\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":0}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "IntNonNegative", "non-negative int"),
  }
}

fn test_int_min_one() -> Result[Unit, Str] {
  let input := "{\"title\":\"S\",\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":1}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "IntPositive", "positive int"),
  }
}

# ---- Array of primitives ----------------------------------------

fn test_array_of_strings() -> Result[Unit, Str] {
  let input := "{\"title\":\"S\",\"type\":\"object\",\"required\":[\"tags\"],\"properties\":{\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "s.required_array(\"tags\", KStr", "array of strings"),
  }
}

# ---- Validator wrapper emitted ----------------------------------

fn test_validator_emitted() -> Result[Unit, Str] {
  let input := "{\"title\":\"Heartbeat\",\"type\":\"object\",\"properties\":{}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "fn validate_heartbeat(j :: jv.Json)",
      "validator wrapper"),
  }
}

# ---- CamelCase → snake_case -------------------------------------

fn test_camel_to_snake() -> Result[Unit, Str] {
  let input := "{\"title\":\"BootNotificationRequest\",\"type\":\"object\",\"properties\":{}}"
  match gen.generate(input) {
    Err(e)  => fail(str.concat("generate failed: ", e)),
    Ok(out) => assert_contains(out, "fn boot_notification_request_schema",
      "snake_case name"),
  }
}

# ---- Bad input rejected -----------------------------------------

fn test_bad_input() -> Result[Unit, Str] {
  match gen.generate("not json") {
    Err(_) => pass(),
    Ok(_)  => fail("invalid JSON should have errored"),
  }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_minimal_schema(),
    test_required_vs_optional(),
    test_enum(),
    test_max_len(),
    test_int_min_zero(),
    test_int_min_one(),
    test_array_of_strings(),
    test_validator_emitted(),
    test_camel_to_snake(),
    test_bad_input(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}
