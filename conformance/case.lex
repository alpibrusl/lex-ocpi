# lex-ocpi — OCPI conformance harness, shared case types (issue #10)
#
# A `Case` is a named, effectful predicate over a target peer. The
# `cpo_harness.lex` and `emsp_harness.lex` binaries are just lists
# of cases plus a `main` that runs them. This file owns the small
# type vocabulary they share so the two harnesses don't drift.
#
# Effects on `run`: `[net, proc]`. Harnesses that need more (`[time]` for
# wall-clock-sensitive cases, `[concurrent]` for race scenarios)
# widen the row at their main entry point.

import "std.int" as int

import "std.list" as list

import "std.str" as str

import "lex-schema/json_value" as jv

import "../src/client" as client

# ---- TargetConfig ---------------------------------------------
type TargetConfig = { base_url :: Str, token :: Str, version :: Str }

fn versions_url(cfg :: TargetConfig) -> Str {
  str.concat(cfg.base_url, "/versions")
}

fn version_detail_url(cfg :: TargetConfig) -> Str {
  str.concat(cfg.base_url, str.concat("/", cfg.version))
}

fn module_url(cfg :: TargetConfig, module :: Str) -> Str {
  str.concat(cfg.base_url, str.concat("/", str.concat(cfg.version, str.concat("/", module))))
}

fn module_item_url(cfg :: TargetConfig, module :: Str, item_id :: Str) -> Str {
  str.concat(module_url(cfg, module), str.concat("/", item_id))
}

# ---- CaseResult ------------------------------------------------
type CaseResult = CasePass | CaseFail(Str) | CaseSkip(Str)

type Case = { name :: Str, run :: (TargetConfig) -> [net, proc] CaseResult }

fn run_case(c :: Case, cfg :: TargetConfig) -> [net, proc] CaseResult {
  c.run(cfg)
}

# Harness self-test: wraps a case so the verdict is inverted. A
# `CaseFail` from the inner case becomes a `CasePass` (the harness
# correctly caught a buggy peer); a `CasePass` becomes a
# `CaseFail` (the case missed a bug it should have flagged). The
# name is annotated `[expect-fail]` so it's obvious in the rollup
# what the case is actually asserting.
fn expect_fail(c :: Case) -> Case {
  { name: str.concat("[expect-fail] ", c.name), run: fn (cfg :: TargetConfig) -> [net, proc] CaseResult {
    match c.run(cfg) {
      CaseFail(_) => CasePass,
      CasePass => CaseFail("expected underlying case to fail, but it passed"),
      CaseSkip(m) => CaseSkip(m),
    }
  } }
}

# ---- Error rendering ------------------------------------------
fn client_error_short(e :: client.ClientError) -> Str {
  match e {
    HttpFailed(m) => str.concat("transport: ", m),
    HttpStatus(info) => str.concat("HTTP ", int.to_str(info.code)),
    BadEnvelope(m) => str.concat("bad envelope: ", m),
    OcpiError(r) => str.concat("OCPI ", int.to_str(r.status_code)),
  }
}

# ---- Per-case record ------------------------------------------
#
# Source of truth for what happened in a case. The text/JSON
# renderers are pure derivations of `records`; one walk, two
# output shapes — callers choose by calling `text_lines` or
# `to_json` on the same Summary.
type CaseRecord = { name :: Str, result :: CaseResult }

# ---- Summary + single-pass runner -----------------------------
#
# Single-pass over the case list — std.list in lex 0.9.5 has no
# `zip`, so the harness folds cases and results together in one
# walk. Each iteration runs the case under [net, proc] and accumulates
# into the running summary.
type Summary = { passed :: Int, failed :: Int, skipped :: Int, total :: Int, records :: List[CaseRecord] }

fn empty_summary() -> Summary {
  { passed: 0, failed: 0, skipped: 0, total: 0, records: [] }
}

fn run_suite(cases :: List[Case], cfg :: TargetConfig) -> [net, proc] Summary {
  list.fold(cases, empty_summary(), fn (acc :: Summary, c :: Case) -> [net, proc] Summary {
    let r := run_case(c, cfg)
    accumulate(acc, c.name, r)
  })
}

fn accumulate(acc :: Summary, name :: Str, r :: CaseResult) -> Summary {
  let records := list.concat(acc.records, [{ name: name, result: r }])
  match r {
    CasePass => { passed: acc.passed + 1, failed: acc.failed, skipped: acc.skipped, total: acc.total + 1, records: records },
    CaseFail(_) => { passed: acc.passed, failed: acc.failed + 1, skipped: acc.skipped, total: acc.total + 1, records: records },
    CaseSkip(_) => { passed: acc.passed, failed: acc.failed, skipped: acc.skipped + 1, total: acc.total + 1, records: records },
  }
}

# ---- Text rendering ------------------------------------------
fn text_lines(s :: Summary) -> List[Str] {
  list.map(s.records, fn (r :: CaseRecord) -> Str {
    render_line(r.name, r.result)
  })
}

fn render_line(name :: Str, r :: CaseResult) -> Str {
  match r {
    CasePass => str.concat("PASS ", name),
    CaseFail(m) => str.concat("FAIL ", str.concat(name, str.concat("  — ", m))),
    CaseSkip(m) => str.concat("SKIP ", str.concat(name, str.concat("  — ", m))),
  }
}

fn rollup(s :: Summary) -> Str {
  str.concat("PASSED ", str.concat(int.to_str(s.passed), str.concat("/", str.concat(int.to_str(s.total), str.concat("  FAILED ", str.concat(int.to_str(s.failed), str.concat("  SKIPPED ", int.to_str(s.skipped))))))))
}

# ---- JSON rendering ------------------------------------------
#
# `to_json` produces a structured report:
#
#   {
#     "summary": { "passed": N, "failed": N, "skipped": N, "total": N },
#     "cases":   [ { "name": "…", "status": "PASS" }, … ]
#   }
#
# Each case entry carries `name` + `status`; FAIL / SKIP entries
# additionally carry `message`. `to_json_str` is the convenience
# stringifier the harness mains call.
fn to_json(s :: Summary) -> jv.Json {
  JObj([("summary", summary_to_json(s)), ("cases", JList(list.map(s.records, record_to_json)))])
}

fn summary_to_json(s :: Summary) -> jv.Json {
  JObj([("passed", JInt(s.passed)), ("failed", JInt(s.failed)), ("skipped", JInt(s.skipped)), ("total", JInt(s.total))])
}

fn record_to_json(r :: CaseRecord) -> jv.Json {
  match r.result {
    CasePass => JObj([("name", JStr(r.name)), ("status", JStr("PASS"))]),
    CaseFail(m) => JObj([("name", JStr(r.name)), ("status", JStr("FAIL")), ("message", JStr(m))]),
    CaseSkip(m) => JObj([("name", JStr(r.name)), ("status", JStr("SKIP")), ("message", JStr(m))]),
  }
}

fn to_json_str(s :: Summary) -> Str {
  jv.stringify(to_json(s))
}

