# Changelog — lex-ocpi

All notable changes to lex-ocpi are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
align with `lex.toml`'s `version` field.

## [Unreleased]

### Added

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

### What's deferred

- **TLS / mTLS transport setup.** OCPI runs over TLS in production; the example serves plain HTTP for simplicity. Real deployments terminate TLS at a reverse proxy.
- **Stateful CSMS-style integration example.** `src/route_io.lex` ships the effectful registry; an end-to-end example threading `[io, time, sql]` handlers + lex-orm persistence is open follow-up.
- **`std.url` / `std.uuid` polish.** Low-severity ergonomic gaps in lex-lang that lex-ocpi doesn't currently hit hard. May file as upstream issues if real consumers report them.

## [0.1.0] — to be tagged

First release. See "Unreleased" above for the full surface.
