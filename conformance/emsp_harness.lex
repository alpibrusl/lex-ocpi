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
import "std.list" as list
import "std.str"  as str

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

# ---- Suite + runner -------------------------------------------

fn suite() -> List[cc.Case] {
  [
    case_versions_returns_ok(),
    case_version_detail_returns_ok(),
    case_authorize_allowed(),
    case_authorize_blocked(),
    case_authorize_not_allowed(),
    case_tariffs_list_returns_ok(),
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
