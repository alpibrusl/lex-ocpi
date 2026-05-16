# Changelog — lex-ocpi

All notable changes to lex-ocpi are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
align with `lex.toml`'s `version` field.

## [Unreleased]

### Added

**Conformance harness — assertions library** (`src/conformance.lex`) — first slice of issue [#10](https://github.com/alpibrusl/lex-ocpi/issues/10):

- `ConformanceError` ADT carrying structured failure detail per violation (`EnvelopeFieldEmpty(name)` / `StatusCodeOutOfBand(code)` / `StatusMessageMissing(code)` / `HeaderMissing(name)` / `HeaderMalformed({ name, why })` / `HeaderEchoMismatch({ name, sent, received })` / `PaginationFieldMissing(name)` / `PaginationFieldInvalid({ name, value, why })` / `DataShape(why)`). `render(e)` turns each variant into a one-line Str for log lines / test failures.
- `classify(code) -> StatusBand` — exhaustive switch over the four spec bands (`Success` 1xxx / `ClientError` 2xxx / `ServerError` 3xxx / `HubError` 4xxx) plus `Unknown` for anything outside.
- `check_envelope(r)` — pure predicate. Asserts `status_code` is in a known band, `timestamp` is non-empty, and `status_message` is non-empty for non-1xxx codes (the spec MUSTs). `check_envelope_all(r)` returns every violation in one pass (vs `check_envelope`'s first-failure return).
- `check_module_request_headers(req)` — asserts `Authorization` starts with `"Token "` (the OCPI fixed scheme), `X-Request-ID` is present, and the from/to party tuples are non-empty + length-shaped (2-char country, 3-char party_id per ISO-3166 + spec). `check_config_request_headers(req)` is the lighter variant for `/versions` and `/credentials` endpoints that don't carry the party tuples.
- `check_response_echoes_request(req, resp_headers)` — asserts the server echoed `X-Request-ID` and `X-Correlation-ID` per spec.
- `check_pagination_headers(resp_headers)` — asserts `X-Total-Count` and `X-Limit` are present and parse as non-negative integers. `check_link_header_present(resp_headers)` checks the `Link` header carries a `rel="next"` marker (RFC 5988 — full grammar parsing is deferred; the common case is what every peer ships).
- `assert_*` wrappers (`assert_envelope` / `assert_module_request_headers` / `assert_response_echoes_request` / `assert_pagination_headers`) return `Result[Unit, Str]` for one-line use in tests — `Str` is the rendered ConformanceError.

`tests/test_conformance.lex` — 31 cases: `classify` × 6 (every band + Unknown high/low), `check_envelope` × 6 (success/client OK; missing-timestamp / unknown-band / message-missing-on-err / empty-message-on-success), `check_envelope_all` × 1 (collects multiple violations), `check_module_request_headers` × 6 (happy / missing-auth / wrong-scheme / missing-rid / missing-from-party / wrong-country-length), header echo × 3 (happy / missing-rid / mismatched-rid), pagination × 5 (happy / missing-total / non-integer-limit / negative-count / Link-rel-missing), `check_authorization` × 1, end-to-end flow × 3 (dispatched envelope passes conformance / fallback envelope passes conformance + is 2xxx / `assert_envelope` one-liner works).

This is the **foundation** layer of the conformance harness. The live-loop scenarios listed in #5 / #7 / #8 (fake HTTP peer that 503s twice, 3-eMSP fanout with one failure, multi-thread idempotency race) need a mock transport that doesn't exist yet — those slot in on top of this library in a future PR. What ships here is everything that's checkable against the *pure* wire-shape of the envelope + header contract, which is most of what OCPI conformance actually means.

**Idempotency cache** (`src/idempotency.lex`) — closes issue [#7](https://github.com/alpibrusl/lex-ocpi/issues/7):

- `std.conc` actor backing an in-memory cache. State is `Map[Str, CacheSlot]` + an LRU list; the slot type is `InFlight | Completed({ response, expires_at_ns })` so the actor naturally distinguishes "someone's running this" from "cached" from "not present".
- Message ADT `TryReserve | Store | Forget | Lookup | Purge` with a parallel reply ADT `Run | Wait | Hit | Miss | Ack`. `cache_handler` is **pure** — testable without `[concurrent]`.
- `CacheKey` keyed on `(method, path, X-Request-ID, OCPI-from-country-code, OCPI-from-party-id)` per the spec. `key_from_request(req)` returns `None` when `X-Request-ID` is empty (uncacheable). `key_str` renders with `|` separators — OCPI wire shapes don't carry pipes in these fields, so collisions don't happen in practice; documented as a known limitation.
- `dispatch_with_cache(reg, cache, cfg, req, timestamp)` — `[concurrent, time]` drop-in for `route.dispatch`. First request with a given key runs the handler and stores the response with TTL; duplicate requests get the cached response without re-invoking. Concurrent duplicates poll the `InFlight` marker until completion or `max_wait_ms` elapses; on timeout the waiter clears the marker and runs the handler itself (avoiding deadlock if the original caller died).
- LRU eviction — capacity-bound; the least-recently-used entry is dropped when a new one would exceed `capacity`. Touching an entry via `TryReserve` or `Lookup` promotes it. `capacity <= 0` is treated as "unbounded".
- TTL expiry — entries drop after `ttl_ms`; the next request with that key re-runs the handler. `default_config()` ships 24h TTL, 50ms poll, 5s max-wait — the 24h matches OCPI's guidance for replay windows. `Purge(now_ns)` manually drops expired entries (in-flight slots are kept; they have no expiry).
- `tests/test_idempotency.lex` — 21 cases: key derivation × 2 (happy + missing-request-id), pure handler × 8 (every TryReserve / Lookup / Forget branch), Purge × 1, LRU × 3 (oldest evicted, touch promotes, capacity-0 unbounded), actor end-to-end × 3 (basic flow, Forget releases, Lookup pending), `dispatch_with_cache` × 4 (dedups same key, distinct keys both run, no-request-id bypasses cache, InFlight + timeout falls back to running the handler).

The genuine multi-thread race (two `dispatch_with_cache` calls from separate threads landing on the same key simultaneously) needs OS-thread scheduling that lex 0.9.3 doesn't expose; the **single-flight semantics** are exercised through the InFlight + timeout fallback path. The SQL-backed variant for multi-replica deployments (`with_idempotency_cache_sql(reg, db)` per the issue spec) wants `route_io.lex` + `std.sql` and is filed as a follow-up.

A small ergonomics note: closure factories like `fn handler_returning(code :: Int) -> (req) -> HandlerResult { fn (_req) -> ... { ... code ... } }` don't capture function parameters cleanly in 0.9.3 — invoking such a factory twice with different arguments returns closures that both capture the FIRST argument. The test suite documents the gotcha and uses distinct named handlers (`handler_1000` / `handler_2000`) as a workaround.

**Outbound push fanout** (`src/push.lex`) — closes issue [#5](https://github.com/alpibrusl/lex-ocpi/issues/5):

- `PushTarget` record — `{ party, base_url, token }` — the per-eMSP coordinates we push to.
- `PushKind` ADT covering the eight spec-shaped operations: `LocationPut` / `LocationPatch` / `EvsePatch` / `ConnectorPatch` / `SessionPut` / `SessionPatch` / `CdrPost` / `TokenPut`. Each variant carries the OCPI tenant tuple (`country_code` / `party_id`) plus the object id(s) needed for its URL plus a `body :: jv.Json` the caller assembles (full object for PUT, partial object for PATCH).
- Pure helpers per kind — `push_method`, `push_url`, `push_body` — with URL builders (`location_url`, `evse_url`, `connector_url`, `session_url`, `token_url`) so callers can reach individual paths without re-assembling the variant.
- `push(policy, from_party, target, kind)` — `[net, time]` single-target push. Builds the request via `client.with_token` + `client.with_party_routing` + `client.with_json_body`, sends through `client.send_with_retry` so transient failures retry per the supplied `RetryPolicy`.
- `push_fanout(policy, from_party, targets, kind)` — `[net, time]` N-target fanout via `list.map` (NOT `flow.parallel_list`, which requires empty-effect closures; the spec reserves true threading for a future scheduler so there's no behaviour difference). Returns one `Result` per target in input order; one target failing does NOT short-circuit the others.
- URL conventions are OCPI 2.2.1 / 2.3.0 — paths include the `{country_code}/{party_id}` multi-tenant segment. `CdrPost` is the one exception (POST `{base}/cdrs` with no tenant in the path; receiver applies its own `OCPI-from-*` headers for routing). v2.1.1's flatter paths can fork later if needed; the modern protocol shape is what production traffic runs on.
- `tests/test_push.lex` — 30 cases: method per variant × 8, URL per variant × 8, body-transparency × 2, URL helpers × 5, `build_request` structural assertions × 6 (CDR + EVSE method/URL, Authorization header, OCPI-from + OCPI-to party tuples, JSON content-type + body present). Hooks-style change-detection (a repo observer firing `notify(...)`) is the doc-mentioned alternative design that doesn't ship in v1; callers wire `push(...)` explicitly into their handlers.

Live-loop fanout tests (3 fake eMSPs, one returning 5xx → 2 OKs + 1 `HttpFailed` in stable order; `Retry-After: 1` honoured) are deferred to the conformance harness in issue [#10](https://github.com/alpibrusl/lex-ocpi/issues/10) — the retry path itself is exercised by `tests/test_retry.lex` already.

**Retry + backoff in the outbound client** (`src/client.lex`) — closes issue [#8](https://github.com/alpibrusl/lex-ocpi/issues/8):

- `RetryPolicy` record carrying `max_attempts` / `initial_delay_ms` / `max_delay_ms` / `multiplier_x100` (integer × 100; 200 = 2.0×; avoids `Float` math) / `jitter` / `respect_retry_after`. Two ready-made constructors: `default_retry_policy()` (5 attempts, 200ms base, 30s cap, 2× growth, jitter on, Retry-After honoured) and `no_retry_policy()` (one-shot, for tests and explicit-no-retry callers).
- New `HttpStatus({ code :: Int, retry_after_ms :: Option[Int] })` variant on `ClientError`. `send` now inspects `resp.status` from `std.http`: 2xx decodes the OCPI envelope (current behaviour), non-2xx surfaces as `HttpStatus` so the retry classifier can see the HTTP code. `BadEnvelope` and `OcpiError` remain reserved for actual envelope-shape / OCPI-logical failures.
- `is_retryable(err)` classifier — pure, total: transport failures retry; HTTP 408 / 429 / 5xx retry; HTTP 4xx (other) gives up; `BadEnvelope` and `OcpiError` give up (the envelope shape and logical-error responses won't change on retry).
- `parse_retry_after_ms(headers)` — integer-seconds form only (`Retry-After: 2` → `Some(2000)`). HTTP-date form is documented as unsupported and returns `None`; the OCPI ecosystem ships the integer form in practice.
- `compute_backoff_ms(attempt, policy, hint)` — composes Retry-After honour + exponential growth + jitter + max-delay clamp. Pure exponential math lives in `exp_backoff_ms` so it's testable without `[time]`; jitter uses `time.mono_ns()` as the entropy source (avoids needing `[rand]`, which is a stub on the current runtime).
- `send_with_retry(req, policy)` — `[net, time]` recursive retry loop. Each iteration: send, on Ok return, on non-retryable Err return immediately, on retryable Err sleep `compute_backoff_ms(...)` and recur until `max_attempts`. Termination bounded by the attempt counter; per-sleep clamped by `time.sleep_ms`'s 60_000 cap.
- `send_with_events(req, policy, observer)` — `[net, time, io]` variant. Observer fires `Attempt({ n, delay_ms, reason })` once per planned retry and `GaveUp({ attempts, last_error })` once at the give-up moment. Successful responses emit no events.
- `tests/test_retry.lex` — 35 cases: classifier × 8 (every error variant, every spec-listed status code), status-code edges × 5 (500 / 599 / 600 boundary / 499 boundary / 200), Retry-After parser × 6 (integer / zero / missing / negative / garbage / HTTP-date documented as unsupported), `retry_after_hint` × 4 (honoured on 503 + 429, suppressed on 500 + transport), backoff math × 6 (default-policy attempts 1/2/3, max-clamp at attempt 10, flat policy with multiplier=100, 1.5× growth chain), `compute_backoff_ms` × 5 (Retry-After honoured + capped + ignored-when-off, no-hint exponential, jitter-in-range), `reason_of` × 4, policy constructors × 2.

Live-loop tests (a fake HTTP target that 503s twice then 200s, or a peer that returns `Retry-After: 1`) are deferred to the conformance harness in issue [#10](https://github.com/alpibrusl/lex-ocpi/issues/10) — everything the retry loop does is exercised here through the pure helpers it delegates to.

**Commands flow — async runtime** (`src/commands_async.lex`) — slice 2 of issue [#4](https://github.com/alpibrusl/lex-ocpi/issues/4); together with slice 1 closes the issue:

- `std.conc` actor backing an in-flight registry keyed on response-id. State is `Map[Str, Option[CommandResult]]` so the actor distinguishes "never registered" (missing) from "registered, pending" (`Some(None)`) from "completed" (`Some(Some(r))`). Message ADT — `Register | Complete | Forget | Lookup` — and a parallel reply ADT — `AckRegistered | AckCompleted | AckForgotten | LookupPending | LookupReady | LookupUnknown` — keep the handler total.
- `inflight_handler` is the **pure** transition function (no `[concurrent]`). The actor is spawned by `new_inflight`; `register` / `complete` / `forget` / `lookup` are thin `conc.tell` / `conc.ask` wrappers so callers don't have to spell the message ADT at every call site.
- `wait_for_result(actor, response_id, timeout_ms, poll_interval_ms)` polls the registry until the CPO's callback has filled in the result or the deadline passes. Splits into a pure `compute_deadline_from(start_ns, timeout_ms)` (testable without `[time]`) and a `[concurrent, time]` `poll_loop` that recurs through `time.sleep_ms`. The runtime caps `sleep_ms` at 60_000 so poll intervals beyond that are silently clamped. Returns `Err(WaitUnknown)` for an id that was never registered, `Err(WaitTimeout)` on deadline expiry.
- `callback_result(response_url, result, token_b64)` — CPO-side `[net]` helper. Encodes the typed `CommandResult` and POSTs it through `client.post_json`. The eMSP's reply (the OCPI envelope on this callback) flows back to the caller so retry policy lives outside this module.
- `parse_result_post(req, extract_response_id)` — eMSP-side **pure** parser of the callback POST. Returns `PostCompleted({ response_id, result }) | PostBadResponseId(why) | PostBadBody(why)`. The user dispatches: on `PostCompleted` call `complete(actor, id, result)` (`[concurrent]`); on either error variant `result_post_handler_result` lifts to `HErr(2001)`. Splitting the parser pure and the `tell` user-side is the same shape as slice 1's `command_handler` — the `route.Handler` type stays effect-free, the user wires the `[concurrent]` tail.
- `tests/test_commands_async.lex` — 23 cases: pure handler (6 — Register / Lookup-unknown / Lookup-pending / Complete-then-Lookup / Complete-without-Register / Forget); actor end-to-end (4 — Register-then-Complete / unknown-id / pending / Forget through real `conc.spawn`); pure deadline math (3); `wait_for_result` (3 — happy completed / unknown id → `WaitUnknown` / 10ms timeout → `WaitTimeout`); pure parser (4 — Completed / bad-response-id / missing-result / unknown-result); pure handler-result mapping (3 — OK / bad-id → 2001 / bad-body → 2001). Live-port round-trip (fake CPO POSTing a real callback to a fake eMSP webhook) is the only thing not covered here and is the natural shape of a future integration suite.

**Commands flow — sync half** (`src/commands.lex`) — slice 1 of issue [#4](https://github.com/alpibrusl/lex-ocpi/issues/4) (sync `CommandResponse`; async `CommandResult` callback runtime is the follow-up slice):

- Three typed ADTs covering the spec's enums — `CommandType` (5 variants — StartSession / StopSession / ReserveNow / CancelReservation / UnlockConnector), `CommandResponseType` (4 — Accepted / Rejected / NotSupported / UnknownSession), `CommandResultType` (9 — Accepted / CanceledReservation / EvseOccupied / EvseInoperative / Failed / NotSupported / Rejected / Timeout / UnknownReservation).
- Total `encode_*` / `decode_*` mappers for all three ADTs (Err on unknown wire strings, never panics).
- `CommandResponse` record bundling `result :: CommandResponseType` + `timeout :: Option[Int]` (v2.1.1 omits, v2.2.1+ includes) + optional `messages :: List[DisplayText]`. Round-trip encode → decode is the identity.
- `CommandResult` record (no `timeout`) for the async-callback side.
- `response_url(body)` — pulls the spec-required `response_url` field out of any command body.
- `command_handler(handle)` — receiver-side glue. Lifts a pure `(body, response_url) -> CommandResponse` into a `route.Handler`. URL-shape `{base}/commands/{TYPE}` is identical across 2.1.1 / 2.2.1 / 2.3.0 so one helper covers all three; the per-version body schemas already shipped in `src/v{211,221,230}/commands.lex` validate the inbound payload via `route.handler_with_schema` ahead of dispatch.
- `submit_command(commands_base, cmd_type, body, token_b64)` — sender-side `[net]` helper. eMSP POSTs the command and decodes the typed `CommandResponse`. `response_url` lives inside `body` and is the eMSP's responsibility to set.
- `tests/test_commands_dispatch.lex` — 31 cases: ADT round-trips for all 18 enum values, negative-decode cases, envelope round-trips for both sides, `response_url` extraction (3 cases), URL builder (3 command types), receiver-side handler (4 cases — accepted branch, rejected branch, missing `response_url` → 2001, captured-url forwarding).

**Real-time token authorization** (`src/authorize.lex` + per-version `src/v{211,221,230}/authorize.lex`) — closes issue [#3](https://github.com/alpibrusl/lex-ocpi/issues/3):

- Shared `AuthorizationResult` ADT (`Allowed | Blocked | Expired | NoCredit | NotAllowed`) wrapping the validated `AuthorizationInfo` JSON. The decision is the variant tag; callers pull `token` / `location` / `authorization_reference` out of the payload as needed.
- `auth.decode` / `auth.encode` — total JSON ↔ ADT mapping. Decoder is robust to unvalidated input (missing field, wrong type, unknown `allowed` string all surface as `Err`).
- Per-version `build_authorize_url` reflecting the path-shape delta — v2.1.1 uses `/tokens/{uid}/authorize`, v2.2.1 + v2.3.0 use `/tokens/{country_code}/{party_id}/{uid}/authorize`.
- Per-version `body_validator` accepting null / empty `{}` (spec's "any-location" form), otherwise delegating to `tokens.validate_location_references`.
- Per-version `authorize_handler(authorize)` — receiver-side glue turning a pure `(token_uid, Option[location_refs]) -> AuthorizationResult` into a `route.Handler` that wraps the encoded result in the standard envelope.
- Per-version `authorize_token(...)` — sender-side `[net]` helper that builds the URL + body, POSTs through `client.post_json`, and decodes the response.
- `tests/test_authorize.lex` — 23 cases covering decoder happy paths (all 5 variants), negative cases (missing field, wrong type, unknown value), decode→encode round-trip, URL builders (all 3 versions), body builders, receiver-side handler (happy paths + missing-token-uid → 2001), wire-shape round-trip through the handler, and body_validator (4 cases).

**OCPI 2.2.1 surface** — full module parity with `elumobility/ocpi-python`'s 2.2.1 surface:

- Locations / EVSE / Connector + GeoLocation / Image / StatusSchedule (`src/v221/locations.lex`)
- Sessions + CdrToken / CdrDimension / ChargingPeriod / Price / ChargingPreferences (`src/v221/sessions.lex`)
- CDRs + CdrLocation / SignedData / SignedValue (`src/v221/cdrs.lex`)
- Tokens + AuthorizationInfo / LocationReferences / EnergyContract (`src/v221/tokens.lex`)
- Tariffs + TariffElement / PriceComponent / TariffRestrictions / EnergyMix (`src/v221/tariffs.lex`)
- Commands + StartSession / StopSession / ReserveNow / CancelReservation / UnlockConnector + CommandResponse / CommandResult (`src/v221/commands.lex`)
- ChargingProfiles + ChargingProfilePeriod / ActiveChargingProfile / SetChargingProfile + ChargingProfileResponse / Result (`src/v221/chargingprofiles.lex`)
- HubClientInfo + ConnectionStatus enum (`src/v221/hubclientinfo.lex`)

**OCPI 2.1.1 surface** — every module ocpi-python ships for 2.1.1, ported:

- Locations / EVSE / Connector + Hours / RegularHours / ExceptionalPeriod
- Sessions (bare `auth_id`, `start_datetime`)
- CDRs (full Location inline, no `cdr_location` split)
- Tokens (no `country_code`/`party_id` on the object)
- Tariffs (required `tariff_alt_text`, no `type` enum)
- Commands (no `CancelReservation`)
- Credentials (**flat** — no `roles[]` array)
- Enums (smaller catalogues: no `APP_USER` token type, no `RESERVATION` status, no `PED_TERMINAL` capability)

**OCPI 2.3.0 surface — FULL** (10/10 modules, matches ocpi-python):

- Enums widened for V2X / DER (ISO 15118-20 plug-charge capabilities, NEMA 5_20 / 6_30 / 10_30 / 14_50 connector types, PaymentStatus, PaymentMethod)
- **Payments module (new in 2.3.0)** — Payment + PaymentInfo + PaymentReference, with PaymentStatus (PENDING / SUCCEEDED / FAILED / REFUNDED / DISPUTED) and PaymentMethod enums
- Locations / EVSE / Connector / GeoLocation / Image / BusinessDetails / StatusSchedule (`src/v230/locations.lex`)
- Sessions + CdrToken + CdrDimension + ChargingPeriod + Price (`src/v230/sessions.lex`)
- CDRs + CdrLocation + SignedData / SignedValue (`src/v230/cdrs.lex`)
- Tokens + EnergyContract + LocationReferences + AuthorizationInfo (`src/v230/tokens.lex`)
- Tariffs + TariffElement + PriceComponent + TariffRestrictions (`src/v230/tariffs.lex`)
- Commands + StartSession / StopSession / ReserveNow / CancelReservation / UnlockConnector + CommandResponse / CommandResult (`src/v230/commands.lex`)
- ChargingProfiles + ChargingProfilePeriod + ActiveChargingProfile + SetChargingProfile + response/result (`src/v230/chargingprofiles.lex`)
- HubClientInfo + ConnectionStatus enum, with PTP role added to the legal `role` set (`src/v230/hubclientinfo.lex`)

**Version-agnostic core:**

- OCPI response envelope encode/parse (`src/envelope.lex`)
- Status code constants + predicates + canonical message map (`src/status.lex`)
- OCPI 1xxx/2xxx/3xxx/4xxx error helpers + schema-error adapter (`src/error.lex`)
- Role / module-id / interface-role / party-id / headers building blocks (`src/role.lex`, `src/module_id.lex`, `src/interface_role.lex`, `src/party.lex`, `src/headers.lex`)
- Versions discovery + endpoint catalogue builders (`src/versions.lex`)
- Credentials handshake (CredentialsRole + BusinessDetails + Image) (`src/credentials.lex`)
- Pure handler registry + dispatch keyed by `(method, module)` (`src/route.lex`)
- Effectful registry with `[io, time, sql]` upper bound for handlers that persist via lex-orm (`src/route_io.lex`)
- Outbound HTTP client wrapping `std.http` with OCPI eight-header preset + envelope decode (`src/client.lex`). Also: `handshake(peer_versions_url, our_token, our_credentials)` — the two-step Versions → Credentials POST registration flow.
- Pagination helpers (`src/pagination.lex`) — `from_query` / `clamp_limit` / `paginate` / `headers` covering the `?offset/?limit` + `X-Total-Count` + `Link: rel="next"` shape every OCPI list endpoint shares
- Date-range filter helpers (`src/filters.lex`) — `from_query` / `apply` covering the `?date_from`/`?date_to` filter every OCPI list endpoint shares. Lexicographic ISO-8601 comparison via `str_lt` / `str_ge` since `std.str` doesn't yet expose a comparator.

**Tooling:**

- `tools/gen.lex` — JSON Schema → `ModelSchema` + validator codegen. Bulk-import the OCA's published schemas instead of hand-rolling every field. Covers top-level `type: object` schemas with primitives, enums, arrays, string-length, int `minimum`, required arrays.

**AI-agent-first surface:**

- `SKILL.md` — agentskills.io-style discovery manifest. Lists every entry point with usage hint, mapping to the underlying Lex SigId an LLM can `lex blame --with-evidence` against.
- `examples {}` blocks on the highest-call-count public fns (envelope.ok / ok_empty / fail / is_success / is_client_error, versions.version / endpoint_*, error.unknown_location / unknown_token, route.ok / fail_with, plus `to_snake` in the codegen tool, `strip_token_prefix` in headers).
- Property-based test driver (`tests/test_property.lex`) — uses `lex-schema/property.generate` to fuzz every validator. Asserts schema/validator round-trip on 8 modules.

**Tests** (14 suites, ~110 cases — all `lex ci`-green):

- `test_envelope.lex` — encode / parse / round-trip / predicates
- `test_status.lex` — spec-exact code values + predicates + message map
- `test_headers.lex` — `from_map` / `to_map` / token extraction / routing predicates
- `test_versions.lex` — Version + Endpoint JSON shape + stock catalogue counts
- `test_credentials.lex` — handshake validator (valid / unknown role / empty roles)
- `test_route.lex` — dispatcher + validator wiring + method mismatch
- `test_client.lex` — pure HTTP request builders (base_request, with_token, with_party_routing, with_json_body)
- `test_v211_schemas.lex` — 2.1.1 Token / Session / Connector / Credentials + version-delta negatives
- `test_v211_more.lex` — 2.1.1 Tariff / CDR / Commands
- `test_v221_schemas.lex` — Token / Session / Connector / EVSE / Location / Command validators
- `test_v221_hubchargingprofiles.lex` — HubClientInfo + ChargingProfiles
- `test_v230_schemas.lex` — 2.3.0 Connector (CHAOJI, NEMA_5_20), EVSE (ISO_15118_20_PLUG_CHARGE), Payment, PaymentInfo
- `test_gen.lex` — codegen output shape (required/optional, enum→StrOneOf, length/min constraints, snake_case)
- `test_pagination.lex` — query parsing, clamp_limit, slice math, has_more, X-Total-Count + Link headers
- `test_filters.lex` — `?date_from`/`?date_to` parsing + lexicographic ISO-8601 filtering + drop-on-missing-last_updated defence
- `test_property.lex` (runs under `[random]`) — schema/validator round-trip

**Examples:**

- `examples/cpo_v221.lex` — minimal OCPI 2.2.1 CPO over `std.net.serve_fn` (no lex-web dep). Versions discovery + a hard-coded Location endpoint.
- `examples/emsp_client.lex` — eMSP side: walks the OCPI discovery flow against a running CPO. Uses `src/client.lex`'s `get_with_token` + structured `ClientError` decode. End-to-end verified against `cpo_v221.lex`: versions → endpoints → location read → unknown-location 2003 envelope.
- `examples/export_schemas.lex` — same `ModelSchema` value, four downstream targets: JSON Schema 2020-12, OpenAPI 3.1 component, TypeScript interface, Pydantic v2 class. The "OCPI schemas are the source of truth for every consumer" story.

**CI:**

- `.github/workflows/lex.yml` — runs `lex ci --no-fmt`, the property driver, the codegen smoke-test, and an HTTP smoke against the example server on every push and PR.

### Upstream issues filed

While building lex-ocpi, the following gaps were filed against the
ecosystem repos:

- [`alpibrusl/lex-lang#435`](https://github.com/alpibrusl/lex-lang/issues/435) — `?` / `try` syntactic sugar for `Result` / `Option` early-return. The pyramid-of-match pattern dominates every validator wrapper and field decoder.
- [`alpibrusl/lex-lang#436`](https://github.com/alpibrusl/lex-lang/issues/436) — `std.net` middleware seam so downstream HTTP libs (lex-ocpi, future lex-rest, …) don't have to depend on `lex-web` just to get URL pattern matching + CORS / body-limit / request-id.
- [`alpibrusl/lex-lang#438`](https://github.com/alpibrusl/lex-lang/issues/438) — `match` guard clauses (`c if pred => …`) for dispatching on derived predicates. Hit by `status.to_message` (15-deep `if-else` chain).
- [`alpibrusl/lex-lang#439`](https://github.com/alpibrusl/lex-lang/issues/439) — Anonymous record literals don't coerce to user-defined parametric record aliases (`type Page[T] = { items :: List[T], … }`). Hit while building `src/pagination.lex`.
- [`alpibrusl/lex-lang#440`](https://github.com/alpibrusl/lex-lang/issues/440) — `std.str` doesn't expose `cmp` / `lt` / `le` / `gt` / `ge` comparators. Hand-rolled in `src/filters.lex` for ISO-8601 lexicographic comparison.

### What's deferred

- **TLS / mTLS transport setup.** OCPI runs over TLS in production; the example serves plain HTTP for simplicity. Real deployments terminate TLS at a reverse proxy.
- **Stateful CSMS-style integration example.** `src/route_io.lex` ships the effectful registry; an end-to-end example threading `[io, time, sql]` handlers + lex-orm persistence is open follow-up.
- **`std.url` / `std.uuid` polish.** Low-severity ergonomic gaps in lex-lang that lex-ocpi doesn't currently hit hard. May file as upstream issues if real consumers report them.

## [0.1.0] — to be tagged

First release. See "Unreleased" above for the full surface.
