# lex-ocpi — OCPI CPO conformance harness binary (issue #10)
#
# Drives a CPO under test through OCPI 2.1.1 / 2.2.1 / 2.3.0
# subsets and asserts every response is spec-shaped.
#
# Entry points:
#
#   main       — full v2.2.1 suite, human-readable
#   main_json  — full v2.2.1 suite, single-line JSON
#   main_v211  — minimal cross-version suite against v2.1.1
#   main_v230  — minimal cross-version suite against v2.3.0
#
# Run:
#   lex run --allow-effects net,io,time conformance/cpo_harness.lex main

import "std.io"    as io
import "std.int"   as int
import "std.list"  as list
import "std.map"   as map
import "std.str"   as str
import "std.http"  as http
import "std.bytes" as bytes

import "lex-schema/json_value" as jv

import "../src/client"   as client
import "../src/envelope" as env

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
    name: "GET /ocpi/{version} returns 1000 envelope (version detail)",
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
    name: "GET /ocpi/{version}/locations returns 1000 envelope",
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
    name: "GET /ocpi/{version}/locations/LOC1 has country_code = NL",
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
    name: "GET /ocpi/{version}/locations/LOC1 has non-empty `evses` array",
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
    name: "GET /ocpi/{version}/locations/LOC9 returns OCPI 2003",
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

fn assert_ocpi_status(
  res     :: Result[jv.Json, client.ClientError],
  want    :: Int,
  label   :: Str
) -> cc.CaseResult {
  match res {
    Ok(_) => CaseFail(str.concat(label,
              str.concat(": expected ", str.concat(int.to_str(want),
                ", got 1000-success")))),
    Err(OcpiError(r)) => if r.status_code == want {
                          CasePass
                        } else {
                          CaseFail(str.concat(label,
                            str.concat(": expected ",
                              str.concat(int.to_str(want),
                                str.concat(", got ",
                                  int.to_str(r.status_code))))))
                        },
    Err(e) => CaseFail(str.concat(label,
                str.concat(": expected OCPI ",
                  str.concat(int.to_str(want),
                    str.concat(", got ", cc.client_error_short(e)))))),
  }
}

fn case_missing_auth_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions without Authorization returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let req := client.base_request("GET", cc.versions_url(cfg))
      assert_ocpi_status(client.send(req), 2000, "missing-auth")
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
      assert_ocpi_status(client.send(req), 2000, "malformed-auth")
    },
  }
}

# New: valid scheme, wrong token value. Spec §4.2 — receiver
# MUST reject unrecognized credentials with a 2000-class envelope.
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

# ---- Spec-required negative paths ----------------------------
#
# Three new spec-shape cases beyond the auth gate:
#   1. Unknown version segment → 3002 ("Unknown / Unsupported version")
#   2. Malformed JSON body on a write → 2001
#   3. Credentials POST happy path → 1000 (echoed credentials body)

fn case_unsupported_version_returns_3002() -> cc.Case {
  {
    name: "GET /ocpi/9.9.9/locations returns OCPI 3002 (unsupported version)",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cfg.base_url, "/9.9.9/locations")
      assert_ocpi_status(client.get_with_token(url, cfg.token),
                         3002, "unsupported-version")
    },
  }
}

fn case_malformed_json_returns_2001() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/commands/START_SESSION with malformed JSON returns 2001",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "commands"), "/START_SESSION")
      assert_ocpi_status(
        client.post_json(url, "{ not valid json", cfg.token),
        2001, "malformed-json")
    },
  }
}

fn case_credentials_post_returns_ok() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/credentials returns 1000 envelope (handshake)",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let body := jv.stringify(JObj([
        ("token", JStr("emsp-secret")),
        ("url",   JStr("http://localhost:9101/ocpi/versions")),
        ("roles", JList([
          JObj([
            ("role",             JStr("EMSP")),
            ("business_details", JObj([("name", JStr("Example eMSP"))])),
            ("country_code",     JStr("DE")),
            ("party_id",         JStr("ABC")),
          ]),
        ])),
      ]))
      match client.post_json(cc.module_url(cfg, "credentials"), body, cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

# ---- CPO-as-receiver: Tokens PUT + Commands POST ---------------

fn case_put_token_returns_ok() -> cc.Case {
  {
    name: "PUT /ocpi/2.2.1/tokens/DE/ABC/RFID-A returns 1000 envelope",
    run: fn (_cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      CaseSkip("std.http PUT broken under lex 0.9.5 — server route wired, client can't reach it")
    },
  }
}

fn command_url(cfg :: cc.TargetConfig, command :: Str) -> Str {
  str.concat(cc.module_url(cfg, "commands"),
    str.concat("/", command))
}

fn start_session_body() -> Str {
  jv.stringify(JObj([
    ("response_url", JStr("http://localhost:9101/ocpi/2.2.1/callback/cmd-1")),
    ("token",        JObj([
      ("country_code", JStr("DE")),
      ("party_id",     JStr("ABC")),
      ("uid",          JStr("RFID-A")),
      ("type",         JStr("RFID")),
      ("contract_id",  JStr("DE-ABC-C12345-T")),
    ])),
    ("location_id",  JStr("LOC1")),
  ]))
}

fn case_post_command_returns_accepted() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/commands/START_SESSION returns ACCEPTED",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match client.post_json(command_url(cfg, "START_SESSION"),
                             start_session_body(), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_command_result(data, "ACCEPTED"),
      }
    },
  }
}

fn check_command_result(data :: jv.Json, want :: Str) -> cc.CaseResult {
  match jv.get_field(data, "result") {
    None    => CaseFail("CommandResponse missing `result`"),
    Some(v) => match jv.as_str(v) {
      None    => CaseFail("`result` is not a string"),
      Some(s) => if s == want {
                   CasePass
                 } else {
                   CaseFail(str.concat("result=", str.concat(s,
                     str.concat(", want ", want))))
                 },
    },
  }
}

# ---- Pagination contract --------------------------------------
#
# OCPI Part I §4.3: list endpoints emit `X-Total-Count`, honor
# `?offset=N&limit=M`, advertise the next page via
# `Link: <…>; rel="next"` when one exists, and filter the result
# set with `?date_from=ISO8601&date_to=ISO8601`. The fake CPO ships
# six Locations whose `last_updated` covers three days; these cases
# walk every dimension of that contract end-to-end.

type RawResponse = {
  status  :: Int,
  headers :: Map[Str, Str],
  body    :: jv.Json,
}

fn send_raw(req :: HttpRequest) -> [net] Result[RawResponse, Str] {
  match http.send(req) {
    Err(_)   => Err("transport: http.send transport error"),
    Ok(resp) => match bytes.to_str(resp.body) {
      Err(e) => Err(str.concat("body not utf-8: ", e)),
      Ok(s)  => match jv.parse(s) {
        Err(pe) => Err(str.concat("body not JSON: ", pe.message)),
        Ok(j)   => Ok({ status: resp.status, headers: resp.headers, body: j }),
      },
    },
  }
}

fn raw_get(url :: Str, token :: Str) -> [net] Result[RawResponse, Str] {
  send_raw(client.with_token(client.base_request("GET", url), token))
}

fn case_locations_emits_x_total_count() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations carries X-Total-Count: 6",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      match raw_get(cc.module_url(cfg, "locations"), cfg.token) {
        Err(m)   => CaseFail(m),
        Ok(resp) => expect_header_eq(resp.headers, "x-total-count", "6"),
      }
    },
  }
}

fn case_locations_limit_truncates_and_links_next() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations?limit=2 returns 2 items + Link rel=\"next\"",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "locations"), "?limit=2")
      match raw_get(url, cfg.token) {
        Err(m)   => CaseFail(m),
        Ok(resp) => and_then(
          expect_list_len(resp.body, 2),
          fn () -> cc.CaseResult { expect_link_next(resp.headers, true) }),
      }
    },
  }
}

fn case_locations_last_page_has_no_link() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations?offset=4&limit=2 omits Link rel=\"next\"",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "locations"),
                            "?offset=4&limit=2")
      match raw_get(url, cfg.token) {
        Err(m)   => CaseFail(m),
        Ok(resp) => and_then(
          expect_list_len(resp.body, 2),
          fn () -> cc.CaseResult { expect_link_next(resp.headers, false) }),
      }
    },
  }
}

fn case_locations_date_from_filters() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations?date_from=2026-05-17 filters by last_updated",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "locations"),
                            "?date_from=2026-05-17T00:00:00Z")
      match raw_get(url, cfg.token) {
        Err(m)   => CaseFail(m),
        Ok(resp) => and_then(
          expect_header_eq(resp.headers, "x-total-count", "2"),
          fn () -> cc.CaseResult { expect_list_len(resp.body, 2) }),
      }
    },
  }
}

fn case_locations_date_to_filters() -> cc.Case {
  {
    name: "GET /ocpi/2.2.1/locations?date_to=2026-05-15T12:00:00Z filters by last_updated",
    run: fn (cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "locations"),
                            "?date_to=2026-05-15T12:00:00Z")
      match raw_get(url, cfg.token) {
        Err(m)   => CaseFail(m),
        Ok(resp) => expect_header_eq(resp.headers, "x-total-count", "1"),
      }
    },
  }
}

# ---- Pagination assertion helpers -----------------------------

fn expect_header_eq(
  headers :: Map[Str, Str],
  name    :: Str,
  want    :: Str
) -> cc.CaseResult {
  match map.get(headers, name) {
    None     => CaseFail(str.concat("missing header: ", name)),
    Some(v)  => if v == want { CasePass }
                else { CaseFail(str.concat(name, str.concat("=", str.concat(v,
                                str.concat(", want ", want))))) },
  }
}

fn expect_link_next(headers :: Map[Str, Str], want_present :: Bool) -> cc.CaseResult {
  let present := match map.get(headers, "link") {
    None    => false,
    Some(v) => str.contains(v, "rel=\"next\""),
  }
  if present == want_present { CasePass }
  else { if want_present {
    CaseFail("Link: rel=\"next\" header expected but missing")
  } else {
    CaseFail("Link: rel=\"next\" header present on last page")
  } }
}

fn expect_list_len(body :: jv.Json, want :: Int) -> cc.CaseResult {
  match jv.get_field(body, "data") {
    None     => CaseFail("envelope missing `data`"),
    Some(d)  => match jv.as_list(d) {
      None    => CaseFail("`data` is not a list"),
      Some(l) => if list.len(l) == want { CasePass }
                 else { CaseFail(str.concat("data has ",
                          str.concat(int.to_str(list.len(l)),
                          str.concat(" items, want ", int.to_str(want))))) },
    },
  }
}

# Chain two assertions without nesting matches. First failure wins;
# the second predicate is only checked when the first passes.
fn and_then(first :: cc.CaseResult, second :: () -> cc.CaseResult) -> cc.CaseResult {
  match first {
    CasePass     => second(),
    CaseFail(m)  => CaseFail(m),
    CaseSkip(m)  => CaseSkip(m),
  }
}

# ---- Suites ---------------------------------------------------

fn suite_v221() -> List[cc.Case] {
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
    case_wrong_token_returns_2000(),
    case_unsupported_version_returns_3002(),
    case_malformed_json_returns_2001(),
    case_credentials_post_returns_ok(),
    case_put_token_returns_ok(),
    case_post_command_returns_accepted(),
    case_locations_emits_x_total_count(),
    case_locations_limit_truncates_and_links_next(),
    case_locations_last_page_has_no_link(),
    case_locations_date_from_filters(),
    case_locations_date_to_filters(),
  ]
}

fn suite_cross_version() -> List[cc.Case] {
  [
    case_versions_returns_ok(),
    case_versions_data_is_list(),
    case_version_detail_returns_ok(),
    case_locations_list_returns_ok(),
    case_location_known_has_country_code(),
    case_location_known_has_evses(),
    case_location_unknown_returns_2003(),
  ]
}

# ---- Entry points ---------------------------------------------

fn default_v221() -> cc.TargetConfig {
  { base_url: "http://localhost:9100/ocpi",
    token:    "cpo-secret",
    version:  "2.2.1" }
}

fn default_v211() -> cc.TargetConfig {
  { base_url: "http://localhost:9100/ocpi",
    token:    "cpo-secret",
    version:  "2.1.1" }
}

fn default_v230() -> cc.TargetConfig {
  { base_url: "http://localhost:9100/ocpi",
    token:    "cpo-secret",
    version:  "2.3.0" }
}

fn run_and_report(
  banner :: Str,
  suite  :: List[cc.Case],
  cfg    :: cc.TargetConfig
) -> [net, io] Int {
  let summary := cc.run_suite(suite, cfg)
  let _ := io.print(banner)
  let _ := list.map(cc.text_lines(summary),
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}

fn main() -> [net, io] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.2.1) ===",
    suite_v221(), default_v221())
}

fn main_json() -> [net, io] Int {
  let summary := cc.run_suite(suite_v221(), default_v221())
  let _ := io.print(cc.to_json_str(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}

fn main_v211() -> [net, io] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.1.1) ===",
    suite_cross_version(), default_v211())
}

fn main_v230() -> [net, io] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.3.0) ===",
    suite_cross_version(), default_v230())
}
