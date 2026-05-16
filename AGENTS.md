# AGENTS.md — lex-ocpi

This file is for AI assistants (Claude Code, Cursor, Aider, Copilot, …)
working in this repo. Humans should read `README.md` first; agents
should read this **first**.

## 1. What this is

OCPI (Open Charge Point Interface) library for the
[Lex language](https://github.com/alpibrusl/lex-lang), in the spirit of
[elumobility/ocpi-python](https://github.com/elumobility/ocpi-python).
Envelope + headers + role catalogues + lex-schema-backed payload
validators + a pure dispatch path, for OCPI 2.2.1 (with 2.1.1 / 2.3.0
slot-in directories planned).

Companion library: [lex-ocpp](https://github.com/alpibrusl/lex-ocpp)
covers the WebSocket-based CP↔CSMS side; lex-ocpi covers the
HTTP-based CPO↔eMSP side.

Built on top of:

- [`alpibrusl/lex-lang`](https://github.com/alpibrusl/lex-lang) — the language + toolchain.
- [`alpibrusl/lex-schema`](https://github.com/alpibrusl/lex-schema) — runtime validation library.
- [`alpibrusl/lex-web`](https://github.com/alpibrusl/lex-web) — HTTP framework (used by examples).
- [`alpibrusl/lex-orm`](https://github.com/alpibrusl/lex-orm) — optional, only when handlers persist via `[sql]`.

## 2. Install the Lex toolchain

CI runs against **v0.9.3** pre-built binaries; use the same locally:

```sh
LEX_VERSION=v0.9.3
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)   TARGET=x86_64-unknown-linux-gnu  ;;
  Linux-aarch64)  TARGET=aarch64-unknown-linux-gnu ;;
  Darwin-x86_64)  TARGET=x86_64-apple-darwin       ;;
  Darwin-arm64)   TARGET=aarch64-apple-darwin      ;;
  *) echo "unsupported platform" >&2; exit 1 ;;
esac
curl -sSfL "https://github.com/alpibrusl/lex-lang/releases/download/${LEX_VERSION}/lex-${LEX_VERSION}-${TARGET}.tar.gz" | tar -xz
sudo install -m 0755 "lex-${LEX_VERSION}-${TARGET}/lex" /usr/local/bin/lex
lex --version
```

Fallback (build from source — needed if you want an off-`main` fix):

```sh
git clone --depth=1 https://github.com/alpibrusl/lex-lang /tmp/lex-lang
cd /tmp/lex-lang && cargo build --release --bin lex
export PATH="/tmp/lex-lang/target/release:$PATH"
```

## 3. Resolve dependencies

lex-ocpi pulls `lex-schema` via `path = "../lex-schema"` in
`lex.toml`. Lay out siblings in a flat directory:

```
~/work/
  ├── lex-ocpi/    ← clone this
  └── lex-schema/  ← clone alpibrusl/lex-schema
```

Then:

```sh
cd ~/work/lex-ocpi
lex pkg install
```

Some downstream consumers will also depend on `lex-web` (HTTP
framework) and `lex-ocpp` (WebSocket-based OCPP companion). Neither
is required to build lex-ocpi itself — clone them only when working
on examples / integrations that reach across libraries.

## 4. Run the full pipeline

```sh
lex ci --no-fmt                # pkg install → check --strict → test
                               # (skip --fmt: source isn't fmt-clean yet)
```

If anything fails, fix it before opening a PR.

## 5. Conventions

### Layout

| Where | What |
|---|---|
| `src/envelope.lex`      | OCPI response envelope encode/parse |
| `src/status.lex`        | OCPI status code constants + predicates |
| `src/error.lex`         | OcpiError ADT + schema-error adapter |
| `src/role.lex`          | CPO / EMSP / Hub / NSP / Other / SCSP / PTP |
| `src/module_id.lex`     | Module identifier strings |
| `src/interface_role.lex`| Sender / Receiver constants |
| `src/party.lex`         | PartyId (country_code + party_id) |
| `src/headers.lex`       | OCPI request header parsing/building |
| `src/versions.lex`      | Versions + VersionDetail + Endpoint |
| `src/credentials.lex`   | Credentials handshake types + schema |
| `src/route.lex`         | Pure handler registry + dispatch |
| `src/v221/*.lex`        | OCPI 2.2.1 surface (enums + validators) |
| `tests/test_*.lex`      | Pure suites; picked up by `lex test` |
| `examples/`             | Runnable CPO / eMSP servers |

### Style

- **Pure core, effect edge.** Everything under `src/` is pure. The
  transport adapter in `examples/<x>.lex` declares `[net, io, time]`
  and threads `time.now_str()` into `route.dispatch`.
- **Function types in records — inline, no aliases.** Type aliases for
  function types don't unfold at call sites in 0.9.x; write
  `handler :: (OcpiRequest) -> HandlerResult` directly in the record
  declaration, not via a `type Handler = ...` alias.
- **Variants as wire identifiers.** Module / role / enum members are
  exposed as `fn name() -> Str` constants, validated via
  `lex-schema`'s `StrOneOf(all_xxx())`. Don't inline string literals
  at call sites — use the constant.
- **Tests return `Int`.** Each suite exports `run_all() -> Int`
  returning the count of failing cases. `lex test` accepts that;
  zero = pass.
- **No `assert`.** Stick with the `Result[Unit, Str]` + counting
  approach that the test suites already use.
- **`route.dispatch` takes an explicit `timestamp` argument.** Pure
  core; the transport supplies `time.now_str()`. Tests pin the
  timestamp for deterministic fixtures.

### Adding a validator

1. Define a `ModelSchema` value in the relevant
   `src/v<XX>/<module>.lex`.
2. Add a `validate_<object>(j)` wrapper that delegates to
   `s.validate(...)`.
3. Add at least one Ok and one Err test case in
   `tests/test_v<XX>_schemas.lex`.

### Adding a status code (rare)

The 1xxx/2xxx/3xxx/4xxx ranges are spec-fixed — don't add new codes
unless you're shipping a new OCPI minor. The library should fail to
encode an unrecognised code rather than invent one.

## 6. Filing upstream issues

Three upstream repos relate to this codebase. Bias toward filing
issues there rather than working around the gap in lex-ocpi source:

- **`alpibrusl/lex-lang`** — language / runtime / toolchain bugs.
- **`alpibrusl/lex-schema`** — runtime validation library.
- **`alpibrusl/lex-web`** — HTTP framework.

When filing, include a minimal reproducer + the affected
downstream surface (file + line) + version info from `lex version`.

## 7. PRs

- Open PR against `main`.
- Title: short and conventional (`feat:`, `fix:`, `ci:`, `docs:`,
  etc).
- Body: summary + test plan + any linked issues.
- The CI workflow at `.github/workflows/lex.yml` runs `lex ci
  --no-fmt` plus smoke tests of the examples. All steps must be
  green before merge.

## 8. Common pitfalls

- **`lex pkg install` fails with `cannot resolve path = "../lex-schema"`.**
  The sibling repo isn't checked out next to lex-ocpi. See section 3.

- **Cross-module schema references fail with `cyclic import`.**
  CDRs reference Tariffs which reference Sessions which reference
  CDR helpers. The library breaks cycles by inlining
  `stub_*_schema()` helpers (see `cdrs.lex`'s
  `stub_tariff_ref_schema()`). Add a new stub rather than introduce
  a cycle.

- **Constructor shadowing warning under `lex check --strict`.**
  Parameters can't be named the same as a top-level fn in the
  same file (the `SHADOW_FN` lint). Rename the param; record fields
  can keep the canonical name (the field-name → param-name → record
  initialization chain just needs to be unambiguous).

- **Effect propagation fails through the dispatcher.** The dispatcher
  is pure; if your handler needs `[io]`, dispatch from a wrapper that
  declares the effect at the transport boundary (see
  `examples/cpo_v221.lex`). Don't try to thread `[io]` through
  `route.dispatch` — it would force the whole registry into
  `[io, time, sql]` upper bound, defeating the pure-core model.
