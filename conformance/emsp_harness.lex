# lex-ocpi — OCPI eMSP conformance harness binary (issue #10)
#
# Counterpart to `cpo_harness.lex`. Drives an eMSP under test
# through a v2.2.1 subset:
#
#   - Versions discovery (same shape as CPO side)
#   - POST /tokens/{cc}/{pid}/{uid}/authorize (the inbound
#     authorize call from a CPO; harness pretends to be the CPO)
#   - GET /tariffs (eMSPs cache tariffs from CPOs and re-serve them)
#
# `examples/` does not ship a fake eMSP yet, so the live CI loop
# is parked: cases marked `CaseSkip` until an `examples/emsp_v221.lex`
# lands. The structure is set up so each concrete eMSP case is a
# one-line addition to `suite()` once there's a real peer to hit.
#
# Run (against a real eMSP at OCPI_TARGET):
#
#   lex run --allow-effects net,io conformance/emsp_harness.lex main

import "std.io"   as io
import "std.list" as list
import "std.str"  as str

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

fn case_authorize_known_token_returns_allowed() -> cc.Case {
  # Placeholder — needs a fake eMSP fixture that responds to
  # POST /tokens/NL/EXM/{uid}/authorize with an AuthorizationInfo
  # envelope. Slot in once `examples/emsp_v221.lex` ships.
  {
    name: "POST /tokens/{uid}/authorize returns AuthorizationInfo",
    run: fn (_cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      CaseSkip("needs examples/emsp_v221.lex fake eMSP")
    },
  }
}

fn case_tariffs_list_returns_ok() -> cc.Case {
  # Placeholder — same reasoning as authorize.
  {
    name: "GET /ocpi/2.2.1/tariffs returns 1000 envelope",
    run: fn (_cfg :: cc.TargetConfig) -> [net] cc.CaseResult {
      CaseSkip("needs examples/emsp_v221.lex fake eMSP")
    },
  }
}

# ---- Suite + runner -------------------------------------------

fn suite() -> List[cc.Case] {
  [
    case_versions_returns_ok(),
    case_authorize_known_token_returns_allowed(),
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
  let cases := suite()
  let results := list.map(cases,
    fn (c :: cc.Case) -> [net] cc.CaseResult { cc.run_case(c, cfg) })
  let summary := cc.summarize(cases, results)
  let _ := io.print("=== lex-ocpi eMSP conformance harness ===")
  let _ := list.map(summary.lines,
    fn (s :: Str) -> [io] Unit { io.print(s) })
  let _ := io.print(cc.rollup(summary))
  if summary.failed > 0 { 1 } else { 0 }
}
