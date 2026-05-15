# lex-ocpi — OCPI 2.1.1 schema validator tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/v211/locations"   as locs
import "../src/v211/sessions"    as sess
import "../src/v211/tokens"      as tokens
import "../src/v211/credentials" as creds

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- Token (2.1.1 — simpler shape than 2.2) ---------------------

fn valid_token() -> jv.Json {
  JObj([
    ("uid",          JStr("12345678")),
    ("type",         JStr("RFID")),
    ("auth_id",      JStr("DE-TNM-C12345678")),
    ("issuer",       JStr("TheNewMotion")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v211_token_valid() -> Result[Unit, Str] {
  assert_ok(tokens.validate_token(valid_token()),
    "valid 2.1.1 token rejected")
}

fn test_v211_token_bad_type() -> Result[Unit, Str] {
  let bad := JObj([
    ("uid",          JStr("12345678")),
    ("type",         JStr("APP_USER")),    # not in 2.1.1
    ("auth_id",      JStr("X")),
    ("issuer",       JStr("X")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("ts")),
  ])
  assert_err(tokens.validate_token(bad),
    "APP_USER is a 2.2 addition; should error in 2.1.1")
}

# ---- Session (2.1.1 — auth_id not cdr_token, no connector_id) ----

fn valid_session() -> jv.Json {
  JObj([
    ("id",             JStr("session-abc")),
    ("start_datetime", JStr("2026-05-15T10:00:00Z")),
    ("kwh",            JFloat(12.5)),
    ("auth_id",        JStr("DE-TNM-C12345678")),
    ("auth_method",    JStr("WHITELIST")),
    ("location",       JStr("LOC1")),
    ("currency",       JStr("EUR")),
    ("total_cost",     JFloat(4.20)),
    ("status",         JStr("ACTIVE")),
    ("last_updated",   JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v211_session_valid() -> Result[Unit, Str] {
  assert_ok(sess.validate_session(valid_session()),
    "valid 2.1.1 session rejected")
}

fn test_v211_session_reservation_status() -> Result[Unit, Str] {
  let bad := JObj([
    ("id",             JStr("s")),
    ("start_datetime", JStr("ts")),
    ("kwh",            JFloat(0.0)),
    ("auth_id",        JStr("A")),
    ("auth_method",    JStr("WHITELIST")),
    ("location",       JStr("LOC1")),
    ("currency",       JStr("EUR")),
    ("total_cost",     JFloat(0.0)),
    ("status",         JStr("RESERVATION")),  # 2.2-only status
    ("last_updated",   JStr("ts")),
  ])
  assert_err(sess.validate_session(bad),
    "RESERVATION is 2.2-only; should error in 2.1.1")
}

# ---- Connector (2.1.1 — voltage/amperage not max_voltage) -------

fn valid_v211_connector() -> jv.Json {
  JObj([
    ("id",           JStr("1")),
    ("standard",     JStr("IEC_62196_T2")),
    ("format",       JStr("SOCKET")),
    ("power_type",   JStr("AC_3_PHASE")),
    ("voltage",      JInt(400)),
    ("amperage",     JInt(32)),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v211_connector_valid() -> Result[Unit, Str] {
  assert_ok(locs.validate_connector(valid_v211_connector()),
    "valid 2.1.1 connector rejected")
}

# ---- Credentials (2.1.1 — flat, no roles array) -----------------

fn valid_v211_credentials() -> jv.Json {
  JObj([
    ("url",          JStr("https://cpo.example.com/ocpi/versions")),
    ("token",        JStr("CPO-TOKEN-ABC")),
    ("party_id",     JStr("EXM")),
    ("country_code", JStr("NL")),
    ("business_details", JObj([
      ("name", JStr("ExampleCPO")),
    ])),
  ])
}

fn test_v211_credentials_valid() -> Result[Unit, Str] {
  assert_ok(creds.validate_credentials_v211(valid_v211_credentials()),
    "valid 2.1.1 credentials rejected")
}

fn test_v211_credentials_no_roles_array() -> Result[Unit, Str] {
  # 2.2-style credentials with a `roles` array should still parse —
  # validation is non-strict (extra fields ignored). Just confirm
  # the basic 2.1.1 shape works.
  let body := JObj([
    ("url",          JStr("https://cpo.example.com/ocpi/versions")),
    ("token",        JStr("X")),
    ("party_id",     JStr("E")),
    ("country_code", JStr("N")),
    # missing business_details — should fail
  ])
  assert_err(creds.validate_credentials_v211(body),
    "missing business_details should error")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_v211_token_valid(),
    test_v211_token_bad_type(),
    test_v211_session_valid(),
    test_v211_session_reservation_status(),
    test_v211_connector_valid(),
    test_v211_credentials_valid(),
    test_v211_credentials_no_roles_array(),
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
