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
import "std.proc"  as proc

import "lex-schema/json_value" as jv

import "../src/client"   as client
import "../src/envelope" as env

import "./case" as cc

# ---- Cases ----------------------------------------------------

fn case_versions_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/versions returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      let req := client.base_request("GET", cc.versions_url(cfg))
      assert_ocpi_status(client.send(req), 2000, "missing-auth")
    },
  }
}

fn case_malformed_auth_returns_2000() -> cc.Case {
  {
    name: "GET /ocpi/versions with Bearer auth returns OCPI 2000",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      let url := str.concat(cfg.base_url, "/9.9.9/locations")
      assert_ocpi_status(client.get_with_token(url, cfg.token),
                         3002, "unsupported-version")
    },
  }
}

fn case_malformed_json_returns_2001() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/commands/START_SESSION with malformed JSON returns 2001",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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

# Parseable but schema-invalid: a credentials POST missing the
# required `token` field. Receiver MUST surface this as a 2001
# envelope with the violation list under `data` (per the validator
# the route registers).
fn case_credentials_missing_field_returns_2001() -> cc.Case {
  {
    name: "POST /ocpi/2.2.1/credentials without `token` returns OCPI 2001",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      let body := jv.stringify(JObj([
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
      assert_ocpi_status(
        client.post_json(cc.module_url(cfg, "credentials"), body, cfg.token),
        2001, "credentials-missing-token")
    },
  }
}

# ---- CPO-as-receiver: Tokens PUT + Commands POST ---------------
#
# std.http's `send` rejects PUT requests under lex 0.9.5 — every
# call returns Err regardless of body shape. Until the upstream
# fix lands, the harness shells out to `curl` via `std.proc.spawn`
# for the PUT cases. Server-side correctness is fully exercised;
# only the client codepath swaps.

type CurlResult = {
  status :: Int,
  body   :: jv.Json,
}

fn put_via_curl(url :: Str, token :: Str, body :: Str) -> [proc] Result[CurlResult, Str] {
  match proc.spawn("curl", [
    "-sS", "-X", "PUT",
    "-H", str.concat("Authorization: Token ", token),
    "-H", "content-type: application/json",
    "-w", "\n%{http_code}",
    "-d", body,
    url,
  ]) {
    Err(m) => Err(str.concat("curl spawn: ", m)),
    Ok(r)  => if r.exit_code == 0 { parse_curl_output(r.stdout) }
              else { Err(str.concat("curl exit ", int.to_str(r.exit_code))) },
  }
}

# curl's `-w "\n%{http_code}"` appends the HTTP status as a trailing
# line. Split it off so the body parses cleanly as JSON.
fn parse_curl_output(out :: Str) -> Result[CurlResult, Str] {
  let parts := str.split(out, "\n")
  let n     := list.len(parts)
  if n < 2 { Err("curl output: no status code line") }
  else {
    let status_str := match list.head(list.reverse(parts)) {
      None    => "",
      Some(s) => s,
    }
    let body_lines := list_drop_last(parts)
    let body_str   := str.join(body_lines, "\n")
    match str.to_int(status_str) {
      None        => Err(str.concat("curl status not an int: ", status_str)),
      Some(code)  => match jv.parse(body_str) {
        Err(pe) => Err(str.concat("curl body not JSON: ", pe.message)),
        Ok(j)   => Ok({ status: code, body: j }),
      },
    }
  }
}

fn list_drop_last(xs :: List[Str]) -> List[Str] {
  list_take(xs, list.len(xs) - 1)
}

fn list_take(xs :: List[Str], n :: Int) -> List[Str] {
  if n <= 0 { [] }
  else { match list.head(xs) {
    None    => [],
    Some(h) => list.concat([h], list_take(list.tail(xs), n - 1)),
  } }
}

# Real PUT through curl. The fake CPO's `put_token` handler returns
# `HOkEmpty` (1000 with null data); the case asserts on the OCPI
# status_code rather than the body shape.
fn case_put_token_returns_ok() -> cc.Case {
  {
    name: "PUT /ocpi/2.2.1/tokens/DE/ABC/RFID-A returns 1000 envelope (via curl)",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      let url := str.concat(cc.module_url(cfg, "tokens"),
                  "/DE/ABC/RFID-A")
      let body := jv.stringify(JObj([
        ("uid",          JStr("RFID-A")),
        ("type",         JStr("RFID")),
        ("contract_id",  JStr("DE-ABC-C12345-T")),
        ("issuer",       JStr("Example Issuer")),
        ("valid",        JBool(true)),
        ("whitelist",    JStr("ALWAYS")),
        ("last_updated", JStr("2026-05-15T10:00:00Z")),
      ]))
      match put_via_curl(url, cfg.token, body) {
        Err(m)   => CaseFail(m),
        Ok(resp) => check_envelope_ok(resp.body),
      }
    },
  }
}

fn check_envelope_ok(body :: jv.Json) -> cc.CaseResult {
  match jv.get_field(body, "status_code") {
    None    => CaseFail("envelope missing `status_code`"),
    Some(v) => match jv.as_int(v) {
      None    => CaseFail("`status_code` not an int"),
      Some(n) => if n >= 1000 and n < 2000 { CasePass }
                 else { CaseFail(str.concat("status_code=", int.to_str(n))) },
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      match client.post_json(command_url(cfg, "START_SESSION"),
                             start_session_body(), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_command_result(data, "ACCEPTED"),
      }
    },
  }
}

# Async-callback round-trip. The CPO is obligated to POST a
# `CommandResult` to whatever `response_url` the eMSP supplied at
# dispatch. The fake eMSP records the latest inbound body under
# GET /callback; the case POSTs a StartSession with response_url set
# to that recorder, waits briefly for the CPO to fire, then asserts
# the recorder has the CommandResult.
fn callback_recorder_url() -> Str { "http://localhost:9101/callback" }

fn case_command_callback_arrives() -> cc.Case {
  {
    name: "POST /commands/START_SESSION delivers CommandResult to response_url",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      let body := jv.stringify(JObj([
        ("response_url", JStr(callback_recorder_url())),
        ("token",        JObj([
          ("country_code", JStr("DE")),
          ("party_id",     JStr("ABC")),
          ("uid",          JStr("RFID-A")),
          ("type",         JStr("RFID")),
          ("contract_id",  JStr("DE-ABC-C12345-T")),
        ])),
        ("location_id",  JStr("LOC1")),
      ]))
      # The fake CPO fires the callback synchronously before
      # returning ACCEPTED; by the time this call returns, the
      # recorder has already received the POST. No sleep needed.
      match client.post_json(command_url(cfg, "START_SESSION"), body, cfg.token) {
        Err(e) => CaseFail(cc.client_error_short(e)),
        Ok(_)  => check_recorder_has_accepted_result(),
      }
    },
  }
}

fn check_recorder_has_accepted_result() -> [net, proc] cc.CaseResult {
  match raw_get(callback_recorder_url(), "any") {
    Err(m) => CaseFail(str.concat("recorder GET: ", m)),
    Ok(resp) => match jv.get_field(resp.body, "data") {
      None    => CaseFail("recorder envelope missing `data`"),
      Some(d) => match d {
        JNull  => CaseFail("no callback recorded yet"),
        _      => match jv.get_field(d, "result") {
          None    => CaseFail("CommandResult body missing `result`"),
          Some(v) => match jv.as_str(v) {
            None    => CaseFail("CommandResult.result is not a string"),
            Some(s) => if s == "ACCEPTED" { CasePass }
                       else { CaseFail(str.concat("result=", s)) },
          },
        },
      },
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
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

# ---- v2.2.1+ module deltas: chargingprofiles, hubclientinfo --
#
# These modules were added in v2.2.1; the v2.3.0 spec adds Payments
# on top. The fake CPO advertises all three under v2.3.0 (and the
# first two under v2.2.1) so the harness can exercise each as a
# happy-path list GET.

fn case_chargingprofiles_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/{version}/chargingprofiles returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "chargingprofiles"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_hubclientinfo_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/{version}/hubclientinfo returns 1000 envelope",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "hubclientinfo"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

fn case_payments_list_returns_ok() -> cc.Case {
  {
    name: "GET /ocpi/{version}/payments returns 1000 envelope (v2.3.0)",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      match client.get_with_token(cc.module_url(cfg, "payments"), cfg.token) {
        Ok(_)  => CasePass,
        Err(e) => CaseFail(cc.client_error_short(e)),
      }
    },
  }
}

# v2.3.0 version_detail advertises Payments on top of the v2.2.1
# module set. Asserts the catalogue is honest about what the fake
# CPO serves.
fn case_v230_detail_lists_payments() -> cc.Case {
  {
    name: "GET /ocpi/2.3.0 version_detail advertises `payments`",
    run: fn (cfg :: cc.TargetConfig) -> [net, proc] cc.CaseResult {
      match client.get_with_token(cc.version_detail_url(cfg), cfg.token) {
        Err(e)   => CaseFail(cc.client_error_short(e)),
        Ok(data) => check_detail_advertises(data, "payments"),
      }
    },
  }
}

fn check_detail_advertises(data :: jv.Json, want :: Str) -> cc.CaseResult {
  match jv.get_field(data, "endpoints") {
    None    => CaseFail("version_detail missing `endpoints`"),
    Some(v) => match jv.as_list(v) {
      None    => CaseFail("`endpoints` is not a list"),
      Some(l) => if list.fold(l, false,
                   fn (acc :: Bool, ep :: jv.Json) -> Bool {
                     if acc { true }
                     else { match jv.get_field(ep, "identifier") {
                       None    => false,
                       Some(i) => match jv.as_str(i) {
                         None    => false,
                         Some(s) => s == want,
                       },
                     } }
                   }) { CasePass }
                 else { CaseFail(str.concat("`endpoints` does not advertise ", want)) },
    },
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
    case_credentials_missing_field_returns_2001(),
    case_put_token_returns_ok(),
    case_post_command_returns_accepted(),
    case_command_callback_arrives(),
    case_locations_emits_x_total_count(),
    case_locations_limit_truncates_and_links_next(),
    case_locations_last_page_has_no_link(),
    case_locations_date_from_filters(),
    case_locations_date_to_filters(),
    case_chargingprofiles_list_returns_ok(),
    case_hubclientinfo_list_returns_ok(),
  ]
}

# v2.3.0-only module deltas: Payments + version_detail catalogue.
# Layered on top of `suite_cross_version` (which is shared by
# v2.1.1 / v2.3.0) for the main_v230 entry point.
fn suite_v230_modules() -> List[cc.Case] {
  [
    case_chargingprofiles_list_returns_ok(),
    case_hubclientinfo_list_returns_ok(),
    case_payments_list_returns_ok(),
    case_v230_detail_lists_payments(),
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
) -> [net, io, proc] Int {
  let summary := cc.run_suite(suite, cfg)
  let _ := io.print(banner)
  let _ := list.map(cc.text_lines(summary),
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}

fn main() -> [net, io, proc] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.2.1) ===",
    suite_v221(), default_v221())
}

fn main_json() -> [net, io, proc] Int {
  let summary := cc.run_suite(suite_v221(), default_v221())
  let _ := io.print(cc.to_json_str(summary))
  if summary.failed > 0 { 1 / 0 } else { 0 }
}

fn main_v211() -> [net, io, proc] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.1.1) ===",
    suite_cross_version(), default_v211())
}

fn main_v230() -> [net, io, proc] Int {
  run_and_report("=== lex-ocpi CPO conformance harness (v2.3.0) ===",
    list.concat(suite_cross_version(), suite_v230_modules()), default_v230())
}
