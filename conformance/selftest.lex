# lex-ocpi — harness self-test (issue #10)
#
# Confidence-builder for the conformance harness itself. Picks a
# representative slice of cases from `cpo_harness.lex`, wraps each
# in `cc.expect_fail`, and runs them against
# `examples/cpo_buggy.lex` — a deliberately-broken CPO that always
# returns `status_code: 999` with an empty data list.
#
# If the wrapped cases all PASS, every underlying assertion
# correctly caught the bug. If any of them FAIL, the harness
# missed something — the case is asserting too loosely (e.g.,
# accepts any 2xx body) and needs tightening.
#
# Run:
#   lex run --allow-effects net,io,time conformance/selftest.lex main
#
# CI prerequisite: `examples/cpo_buggy.lex` must be running on
# port 9103 before this binary is invoked.

import "std.io" as io

import "std.list" as list

import "../src/client" as client

import "./case" as cc

import "./cpo_harness" as ch

fn buggy_target() -> cc.TargetConfig {
  { base_url: "http://localhost:9103/ocpi", token: "any-token", version: "2.2.1" }
}

# Cases the harness self-test exercises. Each is run against the
# buggy CPO; `expect_fail` flips the verdict, so a PASS here means
# the underlying assertion correctly caught the bug.
fn suite() -> List[cc.Case] {
  [cc.expect_fail(ch.case_versions_returns_ok()), cc.expect_fail(ch.case_versions_data_is_list()), cc.expect_fail(ch.case_locations_list_returns_ok()), cc.expect_fail(ch.case_location_known_has_country_code()), cc.expect_fail(ch.case_locations_emits_x_total_count()), cc.expect_fail(ch.case_post_command_returns_accepted())]
}

fn main() -> [net, io, proc] Int {
  let summary := cc.run_suite(suite(), buggy_target())
  let __lex_discard_1 := io.print("=== lex-ocpi harness self-test (against buggy CPO) ===")
  let __lex_discard_2 := list.map(cc.text_lines(summary), fn (s :: Str) -> [io] Unit {
    io.print(s)
  })
  let __lex_discard_3 := io.print(cc.rollup(summary))
  if summary.failed > 0 {
    1 / 0
  } else {
    0
  }
}

