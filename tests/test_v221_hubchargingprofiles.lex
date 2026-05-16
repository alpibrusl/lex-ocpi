# lex-ocpi — HubClientInfo + ChargingProfiles validator tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/v221/hubclientinfo"     as hub
import "../src/v221/chargingprofiles"  as cp

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- HubClientInfo / ClientInfo ---------------------------------

fn valid_client_info() -> jv.Json {
  JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("role",         JStr("CPO")),
    ("status",       JStr("CONNECTED")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_client_info_valid() -> Result[Unit, Str] {
  assert_ok(hub.validate_client_info(valid_client_info()),
    "valid ClientInfo rejected")
}

fn test_client_info_bad_status() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code", JStr("NL")),
    ("party_id",     JStr("TNM")),
    ("role",         JStr("CPO")),
    ("status",       JStr("VACATIONING")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(hub.validate_client_info(bad),
    "bad status should error")
}

fn test_client_info_missing_party() -> Result[Unit, Str] {
  let bad := JObj([
    ("country_code", JStr("NL")),
    ("role",         JStr("CPO")),
    ("status",       JStr("CONNECTED")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
  assert_err(hub.validate_client_info(bad),
    "missing party_id should error")
}

# ---- ChargingProfiles -------------------------------------------

fn valid_charging_profile() -> jv.Json {
  JObj([
    ("charging_rate_unit", JStr("W")),
    ("charging_profile_period", JList([
      JObj([
        ("start_period", JInt(0)),
        ("limit",        JFloat(11000.0)),
      ]),
    ])),
  ])
}

fn test_charging_profile_valid() -> Result[Unit, Str] {
  assert_ok(cp.validate_charging_profile(valid_charging_profile()),
    "valid ChargingProfile rejected")
}

fn test_charging_profile_bad_unit() -> Result[Unit, Str] {
  let bad := JObj([
    ("charging_rate_unit", JStr("HORSEPOWER")),
    ("charging_profile_period", JList([
      JObj([
        ("start_period", JInt(0)),
        ("limit",        JFloat(11000.0)),
      ]),
    ])),
  ])
  assert_err(cp.validate_charging_profile(bad),
    "bad charging_rate_unit should error")
}

fn test_charging_profile_empty_periods() -> Result[Unit, Str] {
  let bad := JObj([
    ("charging_rate_unit", JStr("W")),
    ("charging_profile_period", JList([])),
  ])
  assert_err(cp.validate_charging_profile(bad),
    "empty period list should error")
}

fn test_set_charging_profile_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("charging_profile", valid_charging_profile()),
    ("response_url",
      JStr("https://emsp.example.com/ocpi/2.2.1/chargingprofiles/x")),
  ])
  assert_ok(cp.validate_set_charging_profile(body),
    "valid SetChargingProfile rejected")
}

fn test_charging_profile_response_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("result",  JStr("ACCEPTED")),
    ("timeout", JInt(30)),
  ])
  assert_ok(cp.validate_charging_profile_response(body),
    "valid ChargingProfileResponse rejected")
}

fn test_active_charging_profile_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("start_date_time",  JStr("2026-05-15T10:00:00Z")),
    ("charging_profile", valid_charging_profile()),
  ])
  assert_ok(cp.validate_active_charging_profile(body),
    "valid ActiveChargingProfile rejected")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_client_info_valid(),
    test_client_info_bad_status(),
    test_client_info_missing_party(),
    test_charging_profile_valid(),
    test_charging_profile_bad_unit(),
    test_charging_profile_empty_periods(),
    test_set_charging_profile_valid(),
    test_charging_profile_response_valid(),
    test_active_charging_profile_valid(),
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
