# lex-ocpi — OCPI 2.3.0 schema validator tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/v230/locations" as locs
import "../src/v230/sessions"  as sess
import "../src/v230/tokens"    as tokens
import "../src/v230/payments"  as pay

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- Connector with V2X capability widening --------------------

fn valid_v230_connector() -> jv.Json {
  JObj([
    ("id",           JStr("1")),
    ("standard",     JStr("CHAOJI")),
    ("format",       JStr("CABLE")),
    ("power_type",   JStr("DC")),
    ("max_voltage",  JInt(900)),
    ("max_amperage", JInt(500)),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v230_connector_valid() -> Result[Unit, Str] {
  assert_ok(locs.validate_connector(valid_v230_connector()),
    "valid 2.3.0 connector (CHAOJI)")
}

fn test_v230_connector_nema_5_20() -> Result[Unit, Str] {
  let body := JObj([
    ("id",           JStr("1")),
    ("standard",     JStr("NEMA_5_20")),
    ("format",       JStr("SOCKET")),
    ("power_type",   JStr("AC_1_PHASE")),
    ("max_voltage",  JInt(120)),
    ("max_amperage", JInt(20)),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_ok(locs.validate_connector(body),
    "NEMA_5_20 should be accepted in 2.3.0")
}

# ---- EVSE with ISO_15118_20_PLUG_CHARGE capability --------------

fn test_v230_evse_plug_charge_capability() -> Result[Unit, Str] {
  let body := JObj([
    ("uid",          JStr("EVSE1")),
    ("status",       JStr("AVAILABLE")),
    ("capabilities", JList([JStr("ISO_15118_20_PLUG_CHARGE")])),
    ("connectors",   JList([valid_v230_connector()])),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_ok(locs.validate_evse(body),
    "ISO_15118_20_PLUG_CHARGE should be accepted in 2.3.0")
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

fn valid_v230_session() -> jv.Json {
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

fn test_v230_session_valid() -> Result[Unit, Str] {
  assert_ok(sess.validate_session(valid_v230_session()),
    "valid 2.3.0 session")
}

# ---- Token ------------------------------------------------------

fn test_v230_token_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("uid",          JStr("12345678")),
    ("type",         JStr("RFID")),
    ("contract_id",  JStr("NL-TNM-C12345678-X")),
    ("issuer",       JStr("TNM")),
    ("valid",        JBool(true)),
    ("whitelist",    JStr("ALWAYS")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_ok(tokens.validate_token(body),
    "valid 2.3.0 token")
}

# ---- Payments (new module) --------------------------------------

fn valid_payment() -> jv.Json {
  JObj([
    ("country_code",   JStr("NL")),
    ("party_id",       JStr("TNM")),
    ("id",             JStr("payment-1")),
    ("session_id",     JStr("session-abc")),
    ("method",         JStr("CREDIT_CARD")),
    ("status",         JStr("SUCCEEDED")),
    ("currency",       JStr("EUR")),
    ("amount",         JObj([("excl_vat", JFloat(4.20))])),
    ("authorized_at",  JStr("2026-05-15T10:00:00Z")),
    ("captured_at",    JStr("2026-05-15T10:00:05Z")),
    ("last_updated",   JStr("2026-05-15T10:00:05Z")),
  ])
}

fn test_v230_payment_valid() -> Result[Unit, Str] {
  assert_ok(pay.validate_payment(valid_payment()),
    "valid 2.3.0 payment")
}

fn test_v230_payment_bad_status() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code",  JStr("NL")),
    ("party_id",      JStr("TNM")),
    ("id",            JStr("payment-1")),
    ("method",        JStr("CREDIT_CARD")),
    ("status",        JStr("MAGICAL")),
    ("currency",      JStr("EUR")),
    ("amount",        JObj([("excl_vat", JFloat(4.20))])),
    ("authorized_at", JStr("ts")),
    ("last_updated",  JStr("ts")),
  ])
  assert_err(pay.validate_payment(bad),
    "bad payment status should error")
}

fn test_v230_payment_info_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("payment_id",   JStr("payment-1")),
    ("status",       JStr("SUCCEEDED")),
    ("amount",       JObj([("excl_vat", JFloat(4.20))])),
    ("currency",     JStr("EUR")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_ok(pay.validate_payment_info(body),
    "valid 2.3.0 payment info")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_v230_connector_valid(),
    test_v230_connector_nema_5_20(),
    test_v230_evse_plug_charge_capability(),
    test_v230_session_valid(),
    test_v230_token_valid(),
    test_v230_payment_valid(),
    test_v230_payment_bad_status(),
    test_v230_payment_info_valid(),
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
