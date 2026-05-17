# lex-ocpi — OCPI conformance harness, shared case types (issue #10)
#
# A `Case` is a named, effectful predicate over a target peer. The
# `cpo_harness.lex` and `emsp_harness.lex` binaries are just lists
# of cases plus a `main` that runs them. This file owns the small
# type vocabulary they share so the two harnesses don't drift.
#
# Effects on `run`: `[net]`. Harnesses that need more (`[time]` for
# wall-clock-sensitive cases, `[concurrent]` for race scenarios)
# widen the row at their main entry point.

import "std.int"  as int
import "std.list" as list
import "std.str"  as str

import "../src/client" as client

# ---- TargetConfig ---------------------------------------------

type TargetConfig = {
  base_url :: Str,
  token    :: Str,
  version  :: Str,
}

fn versions_url(cfg :: TargetConfig) -> Str {
  str.concat(cfg.base_url, "/versions")
}

fn version_detail_url(cfg :: TargetConfig) -> Str {
  str.concat(cfg.base_url, str.concat("/", cfg.version))
}

fn module_url(cfg :: TargetConfig, module :: Str) -> Str {
  str.concat(cfg.base_url,
    str.concat("/",
      str.concat(cfg.version,
        str.concat("/", module))))
}

fn module_item_url(cfg :: TargetConfig, module :: Str, item_id :: Str) -> Str {
  str.concat(module_url(cfg, module), str.concat("/", item_id))
}

# ---- CaseResult ------------------------------------------------

type CaseResult =
    CasePass
  | CaseFail(Str)                       # human-readable reason
  | CaseSkip(Str)                       # case not applicable to this peer

# ---- Case ------------------------------------------------------

type Case = {
  name :: Str,
  run  :: (TargetConfig) -> [net] CaseResult,
}

fn run_case(c :: Case, cfg :: TargetConfig) -> [net] CaseResult {
  (c.run)(cfg)
}

# ---- Error rendering ------------------------------------------

fn client_error_short(e :: client.ClientError) -> Str {
  match e {
    HttpFailed(m)    => str.concat("transport: ", m),
    HttpStatus(info) => str.concat("HTTP ", int.to_str(info.code)),
    BadEnvelope(m)   => str.concat("bad envelope: ", m),
    OcpiError(r)     => str.concat("OCPI ", int.to_str(r.status_code)),
  }
}

# ---- Summary + single-pass runner -----------------------------
#
# Single-pass over the case list — std.list in lex 0.9.5 has no
# `zip`, so the harness folds cases and results together in one
# walk. Each iteration runs the case under [net] and accumulates
# into the running summary.

type Summary = {
  passed  :: Int,
  failed  :: Int,
  skipped :: Int,
  total   :: Int,
  lines   :: List[Str],
}

fn empty_summary() -> Summary {
  { passed: 0, failed: 0, skipped: 0, total: 0, lines: [] }
}

fn run_suite(cases :: List[Case], cfg :: TargetConfig) -> [net] Summary {
  list.fold(cases, empty_summary(),
    fn (acc :: Summary, c :: Case) -> [net] Summary {
      let r := run_case(c, cfg)
      accumulate(acc, c.name, r)
    })
}

fn accumulate(acc :: Summary, name :: Str, r :: CaseResult) -> Summary {
  let line := render_line(name, r)
  let lines := list.concat(acc.lines, [line])
  match r {
    CasePass    => { passed: acc.passed + 1, failed: acc.failed,
                     skipped: acc.skipped, total: acc.total + 1,
                     lines: lines },
    CaseFail(_) => { passed: acc.passed, failed: acc.failed + 1,
                     skipped: acc.skipped, total: acc.total + 1,
                     lines: lines },
    CaseSkip(_) => { passed: acc.passed, failed: acc.failed,
                     skipped: acc.skipped + 1, total: acc.total + 1,
                     lines: lines },
  }
}

fn render_line(name :: Str, r :: CaseResult) -> Str {
  match r {
    CasePass     => str.concat("PASS ", name),
    CaseFail(m)  => str.concat("FAIL ", str.concat(name, str.concat("  — ", m))),
    CaseSkip(m)  => str.concat("SKIP ", str.concat(name, str.concat("  — ", m))),
  }
}

fn rollup(s :: Summary) -> Str {
  str.concat("PASSED ",
    str.concat(int.to_str(s.passed),
      str.concat("/",
        str.concat(int.to_str(s.total),
          str.concat("  FAILED ",
            str.concat(int.to_str(s.failed),
              str.concat("  SKIPPED ", int.to_str(s.skipped))))))))
}
