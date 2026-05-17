# lex-ocpi — OCPI CPO conformance harness binary (issue #10)
#
# Drives a CPO under test through a v2.2.1 subset and asserts every
# response is spec-shaped. The pure assertions live in
# `src/conformance.lex`; the live HTTP loop lives here.
#
# Run:
#
#   lex run --allow-effects net,io,time conformance/cpo_harness.lex main
#
# The harness targets `http://localhost:9100/ocpi` with token
# `cpo-secret` by default — matching `examples/cpo_v221.lex`. A real
# deployment overrides via env vars (`OCPI_TARGET`, `OCPI_TOKEN`)
# once those primitives land; for now defaults are hard-coded so
# the CI loop has a single working invocation.
#
# Scope (v2.2.1; grows iteratively — each PR appends cases to
# `suite()` without touching the runner):
#
#   1. GET /ocpi/versions returns 1000 envelope
#   2. GET /ocpi/versions data is a non-empty list
#   3. GET /ocpi/2.2.1 returns 1000 envelope (version detail)
#   4. GET /ocpi/2.2.1/locations returns 1000 envelope
#   5. GET /ocpi/2.2.1/locations/LOC1 has country_code = "NL"
#   6. GET /ocpi/2.2.1/locations/LOC1 has an `evses` array
#   7. GET /ocpi/2.2.1/locations/LOC9 returns OCPI error 2003
#   8. GET /ocpi/wat returns OCPI 2000 (generic client error
#      fallback for unknown paths)

import "std.io"   as io
import "std.int"  as int
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

# Envelope-shape check: the `data` field for `GET /versions` must be
# a JList per spec (§6.1.1). A peer that returns 1000-success with
# scalar / object `data` violates the contract even if the envelope
# parses.
fn case_versions_data_is_list() -> cc.Case {
  {
    name: "GET /ocpi/versions data is a non-empty list",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.versions_url(cfg), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => match data {
          JList(items) => if list.is_empty(items) {
                            CaseFail("data is a list but empty")
                          } else {
                            CasePass
                          },
          _ => CaseFail("data is not a JSON list"),
        },
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

fn case_locations_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "locations"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_location_known_has_country_code() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations/LOC1 has country_code = NL",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := cc.module_item_url(cfg, "locations", "LOC1")
      match client.get_with_token(url, cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_country_code(data, "NL"),
      }
    },
  }
}

fn check_country_code(data :: jv.Json, want :: Str) -> cc.CaseResult {
  match jv.get_field(data, "country_code") {
    None    => CaseFail("data has no country_code field"),
    Some(v) => match jv.as_str(v) {
      None    => CaseFail("country_code is not a string"),
      Some(s) => if s == want {
                   CasePass
                 } else {
                   CaseFail(str.concat("country_code = ", str.concat(s,
                     str.concat(", want ", want))))
                 },
    },
  }
}

# Validates that the Location object includes the `evses` array
# (required field per spec §8.4 with `ListNonEmpty`). A Location
# without EVSEs is structurally invalid even if the envelope is OK.
fn case_location_known_has_evses() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations/LOC1 has non-empty `evses` array",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := cc.module_item_url(cfg, "locations", "LOC1")
      match client.get_with_token(url, cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_has_non_empty_list(data, "evses"),
      }
    },
  }
}

fn check_has_non_empty_list(data :: jv.Json, field :: Str) -> cc.CaseResult {
  match jv.get_field(data, field) {
    None    => CaseFail(str.concat("data missing field: ", field)),
    Some(v) => match v {
      JList(items) => if list.is_empty(items) {
                        CaseFail(str.concat(field, " is empty"))
                      } else {
                        CasePass
                      },
      _ => CaseFail(str.concat(field, " is not a JSON list")),
    },
  }
}

fn case_location_unknown_returns_2003() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations/LOC9 returns OCPI 2003",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := cc.module_item_url(cfg, "locations", "LOC9")
      match client.get_with_token(url, cfg.token) {
        Ok(_) => CaseFail("expected 2003, got 1000-success envelope"),
        Err(OcpiError(r)) => if r.status_code == 2003 {
                              CasePass
                            } else {
                              CaseFail(str.concat("expected 2003, got ",
                                int.to_str(r.status_code)))
                            },
        Err(e) => CaseFail(str.concat("expected OCPI 2003, got ",
                                       cc.client_error_short(e))),
      }
    },
  }
}

# Negative case: a path the registry doesn't know maps to
# status_code 2000 ("Generic client error") via the dispatcher's
# `default_unknown` fallback. The HTTP layer stays 200 — OCPI
# errors travel inside the envelope.
fn case_unknown_path_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/wat returns OCPI 2000 (unknown route)",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cfg.base_url, "/wat")
      match client.get_with_token(url, cfg.token) {
        Ok(_) => CaseFail("expected 2000, got 1000-success envelope"),
        Err(OcpiError(r)) => if r.status_code == 2000 {
                              CasePass
                            } else {
                              CaseFail(str.concat("expected 2000, got ",
                                int.to_str(r.status_code)))
                            },
        Err(e) => CaseFail(str.concat("expected OCPI 2000, got ",
                                       cc.client_error_short(e))),
      }
    },
  }
}

# ---- Suite + runner -------------------------------------------

fn suite() -> List[cc.Case] {
  [
    case_versions_returns_ok(),
    case_versions_data_is_list(),
    case_version_detail_returns_ok(),
    case_locations_list_returns_ok(),
    case_location_known_has_country_code(),
    case_location_known_has_evses(),
    case_location_unknown_returns_2003(),
    case_unknown_path_returns_2000(),
  ]
}

fn default_target() -> cc.TargetConfig {
  { base_url: "http://localhost:9100/ocpi",
    token:    "cpo-secret",
    version:  "2.2.1" }
}

# main exits non-zero when any case fails: divide-by-zero panic
# matches the pattern `tests/test_*.lex` use for `run_all`. CI
# propagates that as the step's exit code.
fn main() -> [net, io] Int {
  let cfg := default_target()
  let summary := cc.run_suite(suite(), cfg)
  let _ := io.print("=== lex-ocpi CPO conformance harness ===")
  let _ := list.map(summary.lines,
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}
