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
# Scope (v2.2.1; grows iteratively — each PR appends cases to
# `suite()` without touching the runner):
#
#    1. GET /ocpi/versions returns 1000 envelope
#    2. GET /ocpi/versions data is a non-empty list
#    3. GET /ocpi/2.2.1 returns 1000 envelope (version detail)
#    4. GET /ocpi/2.2.1/locations returns 1000 envelope
#    5. GET /ocpi/2.2.1/locations/LOC1 has country_code = "NL"
#    6. GET /ocpi/2.2.1/locations/LOC1 has an `evses` array
#    7. GET /ocpi/2.2.1/locations/LOC9 returns OCPI error 2003
#    8. GET /ocpi/wat returns OCPI 2000 (unknown route)
#    9. GET /ocpi/2.2.1/sessions returns 1000 envelope
#   10. GET /ocpi/2.2.1/cdrs returns 1000 envelope
#   11. GET /ocpi/2.2.1/tariffs returns 1000 envelope
#   12. First CDR has total_cost.excl_vat
#   13. First Tariff has non-empty `elements`
#   14. Missing Authorization header returns OCPI 2000
#   15. Bearer-scheme Authorization returns OCPI 2000

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

# ---- Sessions / CDRs / Tariffs list endpoints -----------------

fn case_sessions_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/sessions returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "sessions"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_cdrs_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/cdrs returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "cdrs"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
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

fn case_first_cdr_has_total_cost() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/cdrs first entry has total_cost.excl_vat",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "cdrs"), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_first_cdr_total_cost(data),
      }
    },
  }
}

fn check_first_cdr_total_cost(data :: jv.Json) -> cc.CaseResult {
  match data {
    JList(items) => match list.head(items) {
      None       => CaseFail("cdrs list is empty"),
      Some(cdr)  => match jv.get_field(cdr, "total_cost") {
        None    => CaseFail("first CDR missing total_cost"),
        Some(c) => match jv.get_field(c, "excl_vat") {
          None    => CaseFail("total_cost missing excl_vat"),
          Some(_) => CasePass,
        },
      },
    },
    _ => CaseFail("cdrs data is not a JSON list"),
  }
}

fn case_first_tariff_has_elements() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/tariffs first entry has non-empty `elements`",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "tariffs"), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_first_tariff_elements(data),
      }
    },
  }
}

fn check_first_tariff_elements(data :: jv.Json) -> cc.CaseResult {
  match data {
    JList(items) => match list.head(items) {
      None       => CaseFail("tariffs list is empty"),
      Some(t)    => check_has_non_empty_list(t, "elements"),
    },
    _ => CaseFail("tariffs data is not a JSON list"),
  }
}

# ---- Auth negative cases --------------------------------------
#
# OCPI §4.2 requires `Authorization: Token <b64>` on every request.
# Spec violation → receiver returns a 2000-class envelope (NOT a
# 401 HTTP status — OCPI errors travel inside the envelope, the
# HTTP layer stays 200). We exercise two failure modes:
#
#   - header absent entirely
#   - header present but using a non-`Token` scheme (Bearer / Basic)

fn assert_ocpi_2000(
  res   :: Result[jv.Json, client.ClientError],
  label :: Str
) -> cc.CaseResult {
  match res {
    Ok(_) => CaseFail(str.concat(label, ": expected 2000, got 1000-success")),
    Err(OcpiError(r)) => if r.status_code == 2000 {
                          CasePass
                        } else {
                          CaseFail(str.concat(label,
                            str.concat(": expected 2000, got ",
                              int.to_str(r.status_code))))
                        },
    Err(e) => CaseFail(str.concat(label,
                str.concat(": expected OCPI 2000, got ",
                  cc.client_error_short(e)))),
  }
}

fn case_missing_auth_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions without Authorization returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      # Build the request without calling `with_token` — the
      # Authorization header is absent.
      let req := client.base_request("GET", cc.versions_url(cfg))
      assert_ocpi_2000(client.send(req), "missing-auth")
    },
  }
}

fn case_malformed_auth_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions with Bearer auth returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let req := http.with_header(
        client.base_request("GET", cc.versions_url(cfg)),
        "authorization", "Bearer wrong-scheme")
      assert_ocpi_2000(client.send(req), "malformed-auth")
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
    case_sessions_list_returns_ok(),
    case_cdrs_list_returns_ok(),
    case_tariffs_list_returns_ok(),
    case_first_cdr_has_total_cost(),
    case_first_tariff_has_elements(),
    case_missing_auth_returns_2000(),
    case_malformed_auth_returns_2000(),
  ]
}

fn default_target() -> cc.TargetConfig {
  { base_url: "http://localhost:9100/ocpi",
    token:    "cpo-secret",
    version:  "2.2.1" }
}

fn main() -> [net, io] Int {
  let cfg := default_target()
  let summary := cc.run_suite(suite(), cfg)
  let _ := io.print("=== lex-ocpi CPO conformance harness ===")
  let _ := list.map(summary.lines,
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}
