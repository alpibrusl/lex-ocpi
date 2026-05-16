# lex-ocpi — Credentials module tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/credentials" as creds
import "../src/role"        as role

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- Fixtures ---------------------------------------------------

fn valid_credentials() -> jv.Json {
  JObj([
    ("token", JStr("CPO-TOKEN-ABC123XYZ")),
    ("url",   JStr("https://cpo.example.com/ocpi/versions")),
    ("roles", JList([
      JObj([
        ("role",             JStr("CPO")),
        ("business_details", JObj([
          ("name", JStr("ExampleCPO")),
        ])),
        ("party_id",         JStr("EXM")),
        ("country_code",     JStr("NL")),
      ]),
    ])),
  ])
}

# ---- Tests ------------------------------------------------------

fn test_valid_credentials() -> Result[Unit, Str] {
  assert_ok(creds.validate_credentials_v221(valid_credentials()),
    "valid credentials rejected")
}

fn test_empty_roles() -> Result[Unit, Str] {
  let bad := JObj([
    ("token", JStr("X")),
    ("url",   JStr("https://example.com")),
    ("roles", JList([])),
  ])
  assert_err(creds.validate_credentials_v221(bad),
    "empty roles list should error")
}

fn test_unknown_role() -> Result[Unit, Str] {
  let bad := JObj([
    ("token", JStr("X")),
    ("url",   JStr("https://example.com")),
    ("roles", JList([
      JObj([
        ("role",             JStr("CAPTAIN_OBVIOUS")),
        ("business_details", JObj([("name", JStr("Acme"))])),
        ("party_id",         JStr("ACM")),
        ("country_code",     JStr("US")),
      ]),
    ])),
  ])
  assert_err(creds.validate_credentials_v221(bad),
    "unknown role should error")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_valid_credentials(),
    test_empty_roles(),
    test_unknown_role(),
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
