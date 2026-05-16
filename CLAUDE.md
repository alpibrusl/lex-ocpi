# CLAUDE.md — lex-ocpi

> Read by Claude Code on session start. Other agents (Cursor, Aider,
> Codex, Copilot) read `AGENTS.md` — keep both in sync.

This repository is a **Lex** project (typed-effect language,
content-addressed AST, attestation graph). The discipline below is
part of the task brief; treat it as a contract.

**Project-specific guidelines live in [`AGENTS.md`](./AGENTS.md)** —
read it first. The notes below are the generic Lex contract every
project shares.

## Mandatory reading before writing code

Run these in order:

```sh
lex --version                  # confirm Lex is installed; if missing, see below
lex agent-guidelines           # authoritative idiom rules — read in full
lex skill                      # CLI surface + exit codes (ACLI)
```

`lex agent-guidelines` is the prescriptive contract for this project.
Do not write code until you have read it. The rules are numbered and
stable; this CLAUDE.md exists only to point you at them and add
project-specific overrides.

## The discipline summary

The full rules live in `lex agent-guidelines`. The four that matter
most when you're tempted to skip them:

1. **Narrow effects, always.** `fn foo() -> [fs_write("/tmp/x")] T`,
   not `[fs_write]`, not `[fs_write, fs_read, io]`. If the type checker
   rejects, narrow the **body**, not the signature.
2. **Repair, don't regenerate.** When `lex check` fails, run
   `lex --output json check` to get the structured error, then
   `lex repair --apply --transform '<suggested_transform>'`. Only
   regenerate after two failed repair attempts.
3. **`examples {}` blocks on every pure fn.** They're part of the
   SigId and run at `lex check` time — free regression tests with no
   `tests/` boilerplate.
4. **Use the stdlib.** `std.crypto` not hand-rolled crypto, `std.conc`
   not threads, `std.sql` not string-concat SQL, `std.regex` not
   manual scanners. Reach for raw bytes only after checking the
   stdlib index.

## The loop

Every change goes through the same four steps. **Do not claim a task
done before all four are green.**

```sh
lex check --strict src/        # type-check with extra lints
lex fmt --check src/ tests/    # formatting (must be canonical)
lex test                        # all tests/test_*.lex files
lex ci                          # umbrella: same as the above + pkg install
```

If `lex check` fails, do **not** broaden the effect signature to
make it pass. Investigate the body. See `lex agent-guidelines` § 1.2.

## When in doubt

```sh
lex agent-guidelines        # the rules
lex skill                   # the CLI surface
lex --output json check <file>   # structured errors with rule_tag + suggested_transform
lex blame <fn> --with-evidence   # what attestations already cover this fn
```

Lex toolchain version pinned by this project: see `lex.toml` /
`.github/workflows/lex.yml`. If `lex --version` reports a different
version locally, install the pinned one from
<https://github.com/alpibrusl/lex-lang/releases> before continuing.

## Project-specific overrides

See [`AGENTS.md`](./AGENTS.md) for the full project context (layout,
toolchain pinning, dependency sibling layout, test-suite structure,
upstream-issue triage). The hard constraints worth surfacing here:

- **Pinned toolchain: lex 0.9.3.** CI installs the pre-built release
  binary; install the same locally (`AGENTS.md` §2 has the snippet).
- **Pure core, effect edge.** Anything under `src/` is pure unless
  its filename ends in `_io.lex`. Effects (`[io], [net], [time],
  [sql]`) belong at the transport/handler boundary.
- **No type aliases for function types in records.** Inline the full
  fn signature in record declarations — aliases don't unfold at call
  sites in 0.9.x.
- **Variants are exposed as `fn name() -> Str` constants.** Don't
  inline OCPI status / module / enum string literals at call sites;
  use the constant from `src/status.lex`, `src/module_id.lex`,
  `src/v221/enums.lex`, …
- **Tests return `Int` (failure count).** No `assert`; pass = `0`.
- **The dispatcher takes a `timestamp` arg.** Don't reach for
  `time.now_str()` inside `route.dispatch` — keep the pure core
  effect-free; let the transport adapter supply the timestamp.
