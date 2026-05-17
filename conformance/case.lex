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
#
# Everything a harness needs to point at a peer. `base_url` is the
# `/ocpi` root — cases derive per-version paths from
# `base_url + "/" + version + "/locations"`, etc. `token` is the
# credentials token the harness presents; the peer authenticates
# us with it.

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

# Run a case. Trivial wrapper but keeps the call site readable.
fn run_case(c :: Case, cfg :: TargetConfig) -> [net] CaseResult {
  (c.run)(cfg)
}

# ---- Error rendering ------------------------------------------
#
# `client.ClientError` is the failure path for every `client.*`
# call; cases need to render it consistently in their FailReason
# strings so the harness report is grep-friendly.

fn client_error_short(e :: client.ClientError) -> Str {
  match e {
    HttpFailed(m)    => str.concat("transport: ", m),
    HttpStatus(info) => str.concat("HTTP ", int.to_str(info.code)),
    BadEnvelope(m)   => str.concat("bad envelope: ", m),
    OcpiError(r)     => str.concat("OCPI ", int.to_str(r.status_code)),
  }
}

# ---- Suite summary --------------------------------------------
#
# `summarize` walks a parallel List[Case] + List[CaseResult] to
# produce per-case status lines + a Passed/N rollup. Each harness's
# `main` prints the summary and exits 0 / non-zero based on it.

type Summary = {
  passed :: Int,
  failed :: Int,
  skipped :: Int,
  total :: Int,
  lines :: List[Str],
}

fn summarize(cases :: List[Case], results :: List[CaseResult]) -> Summary {
  let pairs := list.zip(cases, results)
  list.fold(pairs, { passed: 0, failed: 0, skipped: 0, total: 0, lines: [] },
    fn (acc :: Summary, p :: (Case, CaseResult)) -> Summary {
      let c := match p { (cc, _) => cc }
      let r := match p { (_, rr) => rr }
      let line := render_line(c.name, r)
      match r {
        CasePass    => { passed: acc.passed + 1, failed: acc.failed,
                         skipped: acc.skipped, total: acc.total + 1,
                         lines: list.concat(acc.lines, [line]) },
        CaseFail(_) => { passed: acc.passed, failed: acc.failed + 1,
                         skipped: acc.skipped, total: acc.total + 1,
                         lines: list.concat(acc.lines, [line]) },
        CaseSkip(_) => { passed: acc.passed, failed: acc.failed,
                         skipped: acc.skipped + 1, total: acc.total + 1,
                         lines: list.concat(acc.lines, [line]) },
      }
    })
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
