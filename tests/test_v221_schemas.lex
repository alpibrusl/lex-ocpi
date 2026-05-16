# lex-ocpi — OCPI 2.2.1 schema validator tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/v221/locations" as locs
import "../src/v221/sessions"  as sess
import "../src/v221/cdrs"      as cdrs
import "../src/v221/tokens"    as tokens
import "../src/v221/tariffs"   as tariffs
import "../src/v221/commands"  as cmds

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- Token ------------------------------------------------------

fn valid_token() -> jv.Json {
  JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("uid",          JStr("12345678")),
    ("type",         JStr("RFID")),
    ("contract_id",  JStr("NL-TNM-C12345678-X")),
    ("issuer",       JStr("TheNewMotion")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_token_valid() -> Result[Unit, Str] {
  assert_ok(tokens.validate_token(valid_token()), "valid token rejected")
}

fn test_token_missing_required() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code", JStr("NL")),
    ("uid",          JStr("12345678")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(tokens.validate_token(bad), "missing fields should error")
}

fn test_token_bad_type_enum() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("uid",          JStr("12345678")),
    ("type",         JStr("NOT_A_TYPE")),
    ("contract_id",  JStr("NL-TNM-C12345678-X")),
    ("issuer",       JStr("TheNewMotion")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(tokens.validate_token(bad), "bad enum should error")
}

# ---- Session ----------------------------------------------------

fn cdr_token() -> jv.Json {
  JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("uid",          JStr("12345678")),
    ("type",         JStr("RFID")),
    ("contract_id",  JStr("NL-TNM-C12345678-X")),
  ])
}

fn valid_session() -> jv.Json {
  JObj([
    ("country_code",    JStr("NL")),
    ("party_id",        JStr("TNM")),
    ("id",              JStr("session-abc")),
    ("start_date_time", JStr("2026-05-15T10:00:00Z")),
    ("kwh",             JFloat(12.5)),
    ("cdr_token",       cdr_token()),
    ("auth_method",     JStr("WHITELIST")),
    ("location_id",     JStr("LOC1")),
    ("evse_uid",        JStr("EVSE1")),
    ("connector_id",    JStr("1")),
    ("currency",        JStr("EUR")),
    ("status",          JStr("ACTIVE")),
    ("last_updated",    JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_session_valid() -> Result[Unit, Str] {
  assert_ok(sess.validate_session(valid_session()), "valid session rejected")
}

fn test_session_bad_status() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code",    JStr("NL")),
    ("party_id",        JStr("TNM")),
    ("id",              JStr("s")),
    ("start_date_time", JStr("2026-05-15T10:00:00Z")),
    ("kwh",             JFloat(0.0)),
    ("cdr_token",       cdr_token()),
    ("auth_method",     JStr("WHITELIST")),
    ("location_id",     JStr("LOC1")),
    ("evse_uid",        JStr("EVSE1")),
    ("connector_id",    JStr("1")),
    ("currency",        JStr("EUR")),
    ("status",          JStr("ZOMBIE")),
    ("last_updated",    JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(sess.validate_session(bad), "bad status should error")
}

# ---- Connector + EVSE -------------------------------------------

fn valid_connector() -> jv.Json {
  JObj([
    ("id",           JStr("1")),
    ("standard",     JStr("IEC_62196_T2")),
    ("format",       JStr("SOCKET")),
    ("power_type",   JStr("AC_3_PHASE")),
    ("max_voltage",  JInt(400)),
    ("max_amperage", JInt(32)),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_connector_valid() -> Result[Unit, Str] {
  assert_ok(locs.validate_connector(valid_connector()),
    "valid connector rejected")
}

fn test_connector_bad_format() -> Result[Unit, Str] {
  let bad := JObj([
    ("id",           JStr("1")),
    ("standard",     JStr("IEC_62196_T2")),
    ("format",       JStr("HOOK")),
    ("power_type",   JStr("AC_3_PHASE")),
    ("max_voltage",  JInt(400)),
    ("max_amperage", JInt(32)),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(locs.validate_connector(bad), "bad format should error")
}

fn valid_evse() -> jv.Json {
  JObj([
    ("uid",          JStr("EVSE1")),
    ("status",       JStr("AVAILABLE")),
    ("connectors",   JList([valid_connector()])),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_evse_valid() -> Result[Unit, Str] {
  assert_ok(locs.validate_evse(valid_evse()), "valid EVSE rejected")
}

# ---- Location ---------------------------------------------------

fn valid_location() -> jv.Json {
  JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("id",           JStr("LOC1")),
    ("publish",      JBool(true)),
    ("address",      JStr("Stationsplein 1")),
    ("city",         JStr("Amsterdam")),
    ("country",      JStr("NLD")),
    ("coordinates",  JObj([
        ("latitude",  JStr("52.379")),
        ("longitude", JStr("4.900")),
    ])),
    ("evses",        JList([valid_evse()])),
    ("time_zone",    JStr("Europe/Amsterdam")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_location_valid() -> Result[Unit, Str] {
  assert_ok(locs.validate_location(valid_location()),
    "valid location rejected")
}

# ---- Command bodies ---------------------------------------------

fn test_command_response_valid() -> Result[Unit, Str] {
  let r := JObj([
    ("result",  JStr("ACCEPTED")),
    ("timeout", JInt(30)),
  ])
  assert_ok(cmds.validate_command_response(r),
    "valid command response rejected")
}

fn test_stop_session_valid() -> Result[Unit, Str] {
  let r := JObj([
    ("response_url", JStr("https://emsp.example.com/ocpi/2.2.1/commands/STOP/abc")),
    ("session_id",   JStr("session-abc")),
  ])
  assert_ok(cmds.validate_stop_session(r),
    "valid stop_session rejected")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_token_valid(),
    test_token_missing_required(),
    test_token_bad_type_enum(),
    test_session_valid(),
    test_session_bad_status(),
    test_connector_valid(),
    test_connector_bad_format(),
    test_evse_valid(),
    test_location_valid(),
    test_command_response_valid(),
    test_stop_session_valid(),
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
