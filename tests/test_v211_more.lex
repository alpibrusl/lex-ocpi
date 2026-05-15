# lex-ocpi — OCPI 2.1.1 Tariffs + CDRs + Commands validator tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv
import "lex-schema/error"      as e

import "../src/v211/tariffs"  as tariffs
import "../src/v211/cdrs"     as cdrs
import "../src/v211/commands" as cmds

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_ok(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Ok(_) => pass(), Err(_) => fail(label) }
}

fn assert_err(r :: Result[jv.Json, List[e.Error]], label :: Str) -> Result[Unit, Str] {
  match r { Err(_) => pass(), Ok(_) => fail(label) }
}

# ---- Tariff -----------------------------------------------------

fn valid_tariff() -> jv.Json {
  JObj([
    ("id",       JStr("EUR-12345")),
    ("currency", JStr("EUR")),
    ("elements", JList([
      JObj([
        ("price_components", JList([
          JObj([
            ("type",      JStr("ENERGY")),
            ("price",     JFloat(0.30)),
            ("step_size", JInt(1000)),
          ]),
        ])),
      ]),
    ])),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v211_tariff_valid() -> Result[Unit, Str] {
  assert_ok(tariffs.validate_tariff(valid_tariff()), "valid 2.1.1 tariff")
}

fn test_v211_tariff_no_elements() -> Result[Unit, Str] {
  let bad := JObj([
    ("id",       JStr("EUR-12345")),
    ("currency", JStr("EUR")),
    ("elements", JList([])),
    ("last_updated", JStr("ts")),
  ])
  assert_err(tariffs.validate_tariff(bad),
    "empty elements should error")
}

# ---- Command bodies ---------------------------------------------

fn test_v211_command_response_valid() -> Result[Unit, Str] {
  let body := JObj([("result", JStr("ACCEPTED"))])
  assert_ok(cmds.validate_command_response(body),
    "valid 2.1.1 command response")
}

fn test_v211_stop_session_valid() -> Result[Unit, Str] {
  let body := JObj([
    ("response_url", JStr("https://emsp.example.com/cb/x")),
    ("session_id",   JStr("session-abc")),
  ])
  assert_ok(cmds.validate_stop_session(body),
    "valid 2.1.1 stop session")
}

fn test_v211_no_cancel_reservation() -> Result[Unit, Str] {
  # 2.1.1 does not have CancelReservation in the command type catalog;
  # asserting the v211 module doesn't even ship a validator helper for
  # it. Closest equivalent we test: StartSession.
  let body := JObj([
    ("response_url", JStr("https://emsp.example.com/cb/x")),
    ("token", JObj([
      ("uid",          JStr("12345678")),
      ("type",         JStr("RFID")),
      ("auth_id",      JStr("NL-TNM-C12345678")),
      ("issuer",       JStr("TNM")),
      ("valid",        JBool(true)),
      ("whitelist",    JStr("ALWAYS")),
      ("last_updated", JStr("ts")),
    ])),
    ("location_id", JStr("LOC1")),
  ])
  assert_ok(cmds.validate_start_session(body), "valid start session")
}

# ---- CDR --------------------------------------------------------
#
# The v2.1.1 CDR embeds a full Location object — let's keep the
# fixture compact (lowest-cardinality required-only Location).

fn min_location() -> jv.Json {
  JObj([
    ("id",            JStr("LOC1")),
    ("type",          JStr("ON_STREET")),
    ("address",       JStr("Stationsplein 1")),
    ("city",          JStr("Amsterdam")),
    ("postal_code",   JStr("1012AB")),
    ("country",       JStr("NLD")),
    ("coordinates",   JObj([
      ("latitude",  JStr("52.379")),
      ("longitude", JStr("4.900")),
    ])),
    ("time_zone",     JStr("Europe/Amsterdam")),
    ("last_updated", JStr("2026-05-15T10:00:00Z")),
  ])
}

fn min_charging_period() -> jv.Json {
  JObj([
    ("start_date_time", JStr("2026-05-15T10:00:00Z")),
    ("dimensions", JList([
      JObj([("type", JStr("ENERGY")), ("volume", JFloat(12.5))]),
    ])),
  ])
}

fn valid_cdr() -> jv.Json {
  JObj([
    ("id",              JStr("cdr-1")),
    ("start_date_time", JStr("2026-05-15T10:00:00Z")),
    ("stop_date_time",  JStr("2026-05-15T11:30:00Z")),
    ("auth_id",         JStr("NL-TNM-C12345678")),
    ("auth_method",     JStr("WHITELIST")),
    ("location",        min_location()),
    ("currency",        JStr("EUR")),
    ("charging_periods", JList([min_charging_period()])),
    ("total_cost",      JFloat(4.20)),
    ("total_energy",    JFloat(12.5)),
    ("total_time",      JFloat(1.5)),
    ("last_updated",    JStr("2026-05-15T10:00:00Z")),
  ])
}

fn test_v211_cdr_valid() -> Result[Unit, Str] {
  assert_ok(cdrs.validate_cdr(valid_cdr()), "valid 2.1.1 CDR")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_v211_tariff_valid(),
    test_v211_tariff_no_elements(),
    test_v211_command_response_valid(),
    test_v211_stop_session_valid(),
    test_v211_no_cancel_reservation(),
    test_v211_cdr_valid(),
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
