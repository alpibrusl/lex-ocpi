# lex-ocpi — OCPI eMSP conformance harness binary (issue #10)
#
# Counterpart to `cpo_harness.lex`. Drives an eMSP under test
# through a v2.2.1 subset:
#
#   1. GET /ocpi/versions returns 1000 envelope
#   2. GET /ocpi/2.2.1 returns 1000 envelope (version detail)
#   3. POST /tokens/NL/EXM/RFID-A/authorize returns ALLOWED
#   4. POST /tokens/NL/EXM/RFID-C/authorize returns BLOCKED
#   5. POST /tokens/NL/EXM/UNKNOWN/authorize returns NOT_ALLOWED
#   6. GET /ocpi/2.2.1/tariffs returns 1000 envelope
#
# Targets the fake eMSP in `examples/emsp_v221.lex` by default —
# the CI loop spawns that server on port 9101 before invoking the
# harness.
#
# Two entry points, same suite:
#
#   main      — human-readable PASS/FAIL lines + rollup
#   main_json — single-line JSON document for CI dashboards
#
# Run:
#   lex run --allow-effects net,io,time conformance/emsp_harness.lex main
#   lex run --allow-effects net,io,time conformance/emsp_harness.lex main_json

import "std.io"   as io
import "std.int"  as int
import "std.list" as list
import "std.str"  as str
import "std.http" as http

import "lex-schema/json_value" as jv

import "../src/client" as client

import "./case" as cc

# ---- Cases ----------------------------------------------------

fn case_versions_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/versions returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.versions_url(cfg), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_version_detail_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1 returns 1000 envelope (version detail)",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.version_detail_url(cfg), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

# ---- Authorize cases -----------------------------------------

fn authorize_url(cfg :: cc.TargetConfig, uid :: Str) -> Str {
  str.concat(cc.module_url(cfg, "tokens"),
    str.concat("/NL/EXM/",
      str.concat(uid, "/authorize")))
}

fn check_allowed_value(data :: jv.Json, want :: Str) -> cc.CaseResult {
  match jv.get_field(data, "allowed") {
    None    => CaseFail("response data has no `allowed` field"),
    Some(v) => match jv.as_str(v) {
      None    => CaseFail("`allowed` is not a string"),
      Some(s) => if s == want { CasePass }
                 else { CaseFail(str.concat("allowed=", str.concat(s,
                          str.concat(", want ", want)))) },
    },
  }
}

fn case_authorize_allowed() -> cc.Case {
  {
    name: "POST /tokens/NL/EXM/RFID-A/authorize returns ALLOWED",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.post_json(authorize_url(cfg, "RFID-A"), "{}", cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_allowed_value(data, "ALLOWED"),
      }
    },
  }
}

fn case_authorize_blocked() -> cc.Case {
  {
    name: "POST /tokens/NL/EXM/RFID-C/authorize returns BLOCKED",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.post_json(authorize_url(cfg, "RFID-C"), "{}", cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_allowed_value(data, "BLOCKED"),
      }
    },
  }
}

fn case_authorize_not_allowed() -> cc.Case {
  {
    name: "POST /tokens/NL/EXM/UNKNOWN/authorize returns NOT_ALLOWED",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.post_json(authorize_url(cfg, "UNKNOWN"), "{}", cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_allowed_value(data, "NOT_ALLOWED"),
      }
    },
  }
}

fn case_tariffs_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/tariffs returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "tariffs"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

# ---- Auth + spec-required negatives --------------------------
#
# Mirror the CPO negative matrix on the eMSP side. The fake eMSP
# enforces the same gate chain (auth → unsupported-version →
# body-parseable → dispatch), so each of these cases targets one
# rung.

fn assert_ocpi_status(
  r     :: Result[jv.Json, client.ClientError],
  want  :: Int,
  label :: Str
) -> cc.CaseResult {
  match r {
    Ok(_) => CaseFail(str.concat(label, " unexpectedly succeeded")),
    Err(e) => match e {
      OcpiError(env) => if env.status_code == want { CasePass }
                        else { CaseFail(str.concat(label,
                                 str.concat(": expected ",
                                 str.concat(int.to_str(want),
                                 str.concat(", got ",
                                            int.to_str(env.status_code)))))) },
      _ => CaseFail(str.concat(label, str.concat(": ", cc.client_error_short(e)))),
    },
  }
}

fn case_missing_auth_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions without Authorization returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      assert_ocpi_status(
        client.send(client.base_request("GET", cc.versions_url(cfg))),
        2000, "missing-auth")
    },
  }
}

fn case_wrong_token_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions with wrong Token value returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      assert_ocpi_status(
        client.get_with_token(cc.versions_url(cfg), "wrong-secret"),
        2000, "wrong-token")
    },
  }
}

fn case_unsupported_version_returns_3002() -> cc.Case {
  {
    name: "GET /ocpi/9.9.9/tariffs returns OCPI 3002 (unsupported version)",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cfg.base_url, "/9.9.9/tariffs")
      assert_ocpi_status(client.get_with_token(url, cfg.token),
                         3002, "unsupported-version")
    },
  }
}

# ---- CPO-as-sender → eMSP-as-receiver: POST /cdrs ------------

fn happy_cdr_body() -> Str {
  jv.stringify(JObj([
    ("country_code",    JStr("NL")),
    ("party_id",        JStr("EXM")),
    ("id",              JStr("CDR1")),
    ("start_date_time", JStr("2026-05-15T10:00:00Z")),
    ("end_date_time",   JStr("2026-05-15T11:00:00Z")),
    ("cdr_token",       JObj([
      ("country_code", JStr("DE")),
      ("party_id",     JStr("ABC")),
      ("uid",          JStr("RFID-A")),
      ("type",         JStr("RFID")),
      ("contract_id",  JStr("DE-ABC-C12345-T")),
    ])),
    ("auth_method",     JStr("WHITELIST")),
    ("cdr_location",    JObj([
      ("id",                    JStr("LOC1")),
      ("address",               JStr("Stationsplein 1")),
      ("city",                  JStr("Amsterdam")),
      ("country",               JStr("NLD")),
      ("coordinates",           JObj([
        ("latitude",  JStr("52.379")),
        ("longitude", JStr("4.900")),
      ])),
      ("evse_uid",              JStr("EVSE1")),
      ("evse_id",               JStr("NL*EXM*E001")),
      ("connector_id",          JStr("1")),
      ("connector_standard",    JStr("IEC_62196_T2")),
      ("connector_format",      JStr("SOCKET")),
      ("connector_power_type",  JStr("AC_3_PHASE")),
    ])),
    ("currency",        JStr("EUR")),
    ("charging_periods", JList([
      JObj([
        ("start_date_time", JStr("2026-05-15T10:00:00Z")),
        ("dimensions",      JList([
          JObj([
            ("type",   JStr("ENERGY")),
            ("volume", JFloat(15.5)),
          ]),
        ])),
      ]),
    ])),
    ("total_cost",      JObj([("excl_vat", JFloat(5.50))])),
    ("total_energy",    JFloat(15.5)),
    ("total_time",      JFloat(1.0)),
    ("last_updated",    JStr("2026-05-15T10:00:00Z")),
  ]))
}

fn case_post_cdr_returns_ok() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/cdrs with valid body returns 1000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.post_json(cc.module_url(cfg, "cdrs"),
                             happy_cdr_body(), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_post_cdr_invalid_returns_2001() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/cdrs with empty object returns OCPI 2001",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      assert_ocpi_status(
        client.post_json(cc.module_url(cfg, "cdrs"), "{}", cfg.token),
        2001, "cdr-missing-fields")
    },
  }
}

# ---- Suite + runner -------------------------------------------

fn suite() -> List[cc.Case] {
  [
    case_versions_returns_ok(),
    case_version_detail_returns_ok(),
    case_authorize_allowed(),
    case_authorize_blocked(),
    case_authorize_not_allowed(),
    case_tariffs_list_returns_ok(),
    case_missing_auth_returns_2000(),
    case_wrong_token_returns_2000(),
    case_unsupported_version_returns_3002(),
    case_post_cdr_returns_ok(),
    case_post_cdr_invalid_returns_2001(),
  ]
}

fn default_target() -> cc.TargetConfig {
  { base_url: "http://localhost:9101/ocpi",
    token:    "emsp-secret",
    version:  "2.2.1" }
}

fn main() -> [net, io] Int {
  let cfg := default_target()
  let summary := cc.run_suite(suite(), cfg)
  let _ := io.print("=== lex-ocpi eMSP conformance harness ===")
  let _ := list.map(cc.text_lines(summary),
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}

# Machine-readable variant. Emits a single-line JSON document with
# the per-case breakdown + counts; useful for CI dashboards that
# parse stdout. Exit code matches `main`: non-zero iff any case
# failed.
fn main_json() -> [net, io] Int {
  let cfg := default_target()
  let summary := cc.run_suite(suite(), cfg)
  let _ := io.print(cc.to_json_str(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}
