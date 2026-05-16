# lex-ocpi

OCPI (Open Charge Point Interface) library for the
[Lex language](https://github.com/alpibrusl/lex-lang), in the spirit of
[elumobility/ocpi-python](https://github.com/elumobility/ocpi-python): the same
shape — pydantic-style payload validation, role-based module catalogues
(CPO / eMSP / PTP), and a fixed wire envelope — reworked for Lex's effect
system, variant ADTs, and pure-core / effect-edge split.

Built on top of [lex-schema](https://github.com/alpibrusl/lex-schema) for
payload validation. Pairs cleanly with
[lex-web](https://github.com/alpibrusl/lex-web)'s router for richer HTTP
transports, but the library itself only depends on lex-schema — the
shipped example drives the OCPI dispatcher over `std.net.serve_fn`
directly.

Requires **lex-lang 0.9.4+**.

Companion library: [lex-ocpp](https://github.com/alpibrusl/lex-ocpp) covers the
CP↔CSMS side of EV charging (WebSocket-based). lex-ocpi covers the
CPO↔eMSP side (HTTP/REST-based).

## What it ships

- **OCPI response envelope** (`src/envelope.lex`). Encode and decode
  the standard `{data, status_code, status_message, timestamp}` wrapper
  every OCPI response carries; total error handling — malformed
  envelopes surface as a typed `EnvelopeError`, never a VM panic.
- **OCPI status codes** (`src/status.lex`). Wire-exact constants for
  every code in the spec catalog (1000-success / 2xxx-client /
  3xxx-server / 4xxx-hub) plus the predicates and message map.
- **Request headers** (`src/headers.lex`). Parse + emit the eight
  OCPI headers (Authorization, X-Request-ID, X-Correlation-ID, plus
  the four-party-routing `OCPI-from-/to-{country-code,party-id}`).
- **Role catalogue** (`src/role.lex`). CPO / eMSP / Hub / NSP / Other
  / SCSP / PTP constants and a version-keyed `all_roles_*()` set.
- **Module identifiers** (`src/module_id.lex`). Locations / Sessions
  / CDRs / Tokens / Tariffs / Commands / ChargingProfiles /
  HubClientInfo / Credentials / Versions / Payments — per-version
  catalog lists.
- **Versions module** (`src/versions.lex`). `Version`, `VersionDetail`,
  `Endpoint` (with Sender/Receiver split). Stock CPO / eMSP endpoint
  builders so the version-detail response is one call.
- **Credentials module** (`src/credentials.lex`). `Credentials`,
  `CredentialsRole`, `BusinessDetails`, `Image` types and the v2.2.1
  validator.
- **Handler registry + dispatch** (`src/route.lex`). Register pure
  handlers keyed by `(method, module)`; an optional per-route
  validator runs *before* the handler and surfaces every failing
  field at once as a `2001` envelope.
- **OCPI 2.2.1 surface** (`src/v221/`). Full enums catalog
  (`enums.lex`), and pydantic-style validators for **every** standard
  module object — Locations / EVSE / Connector, Sessions, CDRs,
  Tokens, Tariffs, Commands, **ChargingProfiles** (`SetChargingProfile`,
  `ActiveChargingProfile`, profile/response/result), **HubClientInfo**
  (`ClientInfo`).
- **JSON Schema → ModelSchema codegen** (`tools/gen.lex`). Reads an
  OCA-published JSON Schema doc and emits a ready-to-paste `ModelSchema`
  + `validate_<name>` wrapper. Bulk-import the rest of the OCPI surface
  without hand-rolling every field. Coverage: primitives, arrays, enums,
  string-length, int-minimum, required arrays.
- **Property-based test driver** (`tests/test_property.lex`). Generates
  schema-conforming payloads via `lex-schema/property` and asserts every
  sample validates — the schema *is* the spec. Runs under `[random]`.
- **Agent skill manifest** (`SKILL.md`). Discovery surface an LLM agent
  reads to emit OCPI code against this library; every entry maps to a
  Lex function with a stable `SigId`.
- **OCPI 2.1.1 surface** (`src/v211/`). Full module set: enums,
  Locations, Sessions, CDRs, Tokens, Tariffs, Commands,
  Credentials. The spec deltas vs 2.2.1 baked in: flat Credentials
  (no `roles[]`), bare `auth_id` (no `CdrToken`), no
  `CancelReservation`, smaller enum catalogues.
- **OCPI 2.3.0 surface** (`src/v230/`). Full 10-module parity:
  enums widened for V2X / ISO 15118-20 + DER (NEMA connector types,
  `ISO_15118_20_PLUG_CHARGE` capability), Locations / Sessions /
  CDRs / Tokens / Tariffs / Commands / ChargingProfiles /
  HubClientInfo (with PTP role), and the **new Payments module**
  (`Payment` + `PaymentInfo` + payment method / status enums).
- **Outbound HTTP client** (`src/client.lex`). Wraps `std.http`
  with the OCPI eight-header preset (`Authorization: Token …`,
  `X-Request-ID`, `X-Correlation-ID`, the four `OCPI-from/to-*`)
  and the envelope-decode happy path. Returns `ClientError` —
  `HttpFailed` (transport), `BadEnvelope` (decode), `OcpiError`
  (2xxx/3xxx/4xxx envelope). Effect: `[net]`.
- **Real-time token authorization** (`src/authorize.lex` +
  `src/v{211,221,230}/authorize.lex`). Both sides of the
  `POST /tokens/.../authorize` flow that runs before every charge
  session start: a shared `AuthorizationResult` ADT
  (`Allowed | Blocked | Expired | NoCredit | NotAllowed` wrapping
  the validated `AuthorizationInfo`); per-version URL builders
  reflecting the path-shape delta between v2.1.1 and v2.2.1+v2.3.0;
  a `body_validator` that accepts null / empty `{}` per spec;
  an `authorize_handler(authorize)` that lifts a pure
  `(token_uid, Option[location_refs]) -> AuthorizationResult` into
  a `route.Handler`; and a sender-side `authorize_token(...)` that
  POSTs and decodes the response. Effect: pure for everything
  except `authorize_token` (`[net]`).
- **Effectful registry** (`src/route_io.lex`). Lex-ocpp parity:
  handlers carry an `[io, time, sql]` upper bound so they can log
  via `io.print`, stamp `last_updated`, and persist via lex-orm's
  `[sql]`-flavoured helpers.
- **Pagination** (`src/pagination.lex`). `PageRequest { offset, limit }`
  parsed from a query map with sane defaults (offset=0, limit=50) and
  negative-clamping; `clamp_limit` for the spec-mandated server cap;
  `paginate` returns a `Page { items, offset, limit, total }`; `headers`
  emits the standard OCPI shape (`X-Total-Count`, `X-Limit`, and a
  `Link: <url>; rel="next"` when more pages exist).
- **Date-range filters** (`src/filters.lex`). `DateRange { date_from,
  date_to }` parsed from a query map; `apply(items, range)` drops
  items outside `[date_from, date_to)` via lexicographic ISO-8601
  comparison — the other half of every OCPI list endpoint's contract
  (`?date_from=` / `?date_to=` alongside `?offset=` / `?limit=`).

## Quickstart

```lex
import "lex-ocpi/route"           as route
import "lex-ocpi/envelope"        as env
import "lex-ocpi/module_id"       as mid
import "lex-ocpi/v221/locations"  as locs

import "lex-schema/json_value"    as jv
import "std.time"                 as time

# Handlers are pure — request in, response payload out.
fn get_locations(_req :: route.OcpiRequest) -> route.HandlerResult {
  route.ok_list([])     # real CPOs page through their location DB here
}

# Build the registry — schema validation runs before the handler.
fn registry() -> route.Registry {
  route.new()
    |> fn (r) { route.handler(r, route.get(), mid.locations(), get_locations) }
}

# Pure dispatch — takes an OcpiRequest, returns an OcpiResponse.
# Pair with lex-web's router for the HTTP transport (see
# `examples/cpo_v221.lex`).
fn handle(req :: route.OcpiRequest) -> [time] env.OcpiResponse {
  route.dispatch(registry(), req, time.now_str())
}
```

Run the example over real HTTP:

```bash
lex run --allow-effects net,io,time examples/cpo_v221.lex main
# Listening on http://localhost:9100/ocpi/...

curl -H "Authorization: Token cpo-secret" \
     http://localhost:9100/ocpi/versions
# {"data":[{"version":"2.2.1","url":"..."}],"status_code":1000,"timestamp":"..."}

curl -H "Authorization: Token cpo-secret" \
     http://localhost:9100/ocpi/2.2.1/locations/LOC1
# {"data":{"country_code":"NL","party_id":"EXM",...},"status_code":1000,...}
```

## Repository layout

```
lex.toml                  package manifest (lex 0.9.4+)
src/
  envelope.lex            OCPI response envelope (data/status_code/message/timestamp)
  status.lex              Status code constants + predicates + message map
  error.lex               OcpiError ADT + schema-error adapter
  role.lex                CPO / EMSP / Hub / NSP / Other / SCSP / PTP
  module_id.lex           Module identifier strings
  interface_role.lex      Sender / Receiver
  party.lex               PartyId (country_code + party_id)
  headers.lex             OCPI request header parsing/building
  versions.lex            Versions + VersionDetail + Endpoint
  credentials.lex         Credentials handshake objects + schema
  route.lex               Pure handler registry + dispatch
  route_io.lex            Effectful registry (`[io, time, sql]` upper bound)
  client.lex              Outbound OCPI HTTP client (`[net]`) + handshake helper
  authorize.lex           Shared AuthorizationResult ADT + decode/encode
  pagination.lex          ?offset/?limit parsing + Page + Link/X-Total-Count headers
  filters.lex             ?date_from/?date_to ISO-8601 range filtering
  v211/                   OCPI 2.1.1 surface — full (enums + credentials +
                                                 locations + sessions + tokens +
                                                 cdrs + tariffs + commands +
                                                 authorize)
  v221/
    enums.lex             OCPI 2.2.1 enums (LocationType, ConnectorType, ...)
    locations.lex         Location + EVSE + Connector schemas
    sessions.lex          Session + CdrToken + ChargingPeriod schemas
    cdrs.lex              CDR + CdrLocation + SignedData schemas
    tokens.lex            Token + AuthorizationInfo schemas
    tariffs.lex           Tariff + TariffElement + PriceComponent schemas
    commands.lex          Start/Stop/Reserve/Cancel/Unlock + response schemas
    chargingprofiles.lex  ChargingProfile + Set/Active/Result schemas
    hubclientinfo.lex     ClientInfo + ConnectionStatus enum
    authorize.lex         Real-time POST /tokens/{cc}/{pid}/{uid}/authorize
  v230/                   OCPI 2.3.0 surface — full (enums + 9 modules
                                                 + Payments NEW)
    enums.lex             V2X / ISO 15118-20 plug-charge / NEMA connectors
    locations.lex         Location + EVSE + Connector with v2.3 enum widening
    sessions.lex          Session + CdrToken + ChargingPeriod
    cdrs.lex              CDR + CdrLocation + SignedData
    tokens.lex            Token + AuthorizationInfo
    tariffs.lex           Tariff + TariffElement
    commands.lex          Start/Stop/Reserve/Cancel/Unlock
    chargingprofiles.lex  ChargingProfile + Set/Active/Result
    hubclientinfo.lex     ClientInfo (with PTP role)
    payments.lex          Payment + PaymentInfo + PaymentReference (NEW)
    authorize.lex         Real-time POST /tokens/{cc}/{pid}/{uid}/authorize
tools/
  gen.lex                 JSON Schema → ModelSchema codegen
tests/
  test_envelope.lex                   Envelope encode / parse / round-trip
  test_status.lex                     Status code constants + predicates
  test_headers.lex                    Header from_map / to_map / token extraction
  test_versions.lex                   Versions discovery JSON shape
  test_credentials.lex                Credentials validator
  test_route.lex                      Dispatcher + validator wiring
  test_client.lex                     Outbound HTTP client header builders
  test_authorize.lex                  Token-authorize ADT + handler + URL/body builders
  test_pagination.lex                 PageRequest parse + paginate + headers
  test_filters.lex                    DateRange parse + apply + str ordering
  test_v211_schemas.lex               v2.1.1 spec-delta validators
  test_v211_more.lex                  v2.1.1 Tariff / Command / CDR validators
  test_v221_schemas.lex               v2.2.1 per-object validator tests
  test_v221_hubchargingprofiles.lex   ChargingProfiles + HubClientInfo validators
  test_v230_schemas.lex               v2.3.0 validators (Payments, PTP role, ...)
  test_gen.lex                        JSON Schema → ModelSchema codegen
  test_property.lex                   Property-based fuzz driver (random)
examples/
  cpo_v221.lex                        Minimal OCPI 2.2.1 CPO over HTTP
  emsp_client.lex                     eMSP-side discovery + read using src/client.lex
  export_schemas.lex                  Schema → TS / Pydantic / JSON Schema / OpenAPI
SKILL.md                              Agent skill manifest
```

## Design

### Pure-core, effect-edge

The dispatcher is pure. Envelope construction, validation, handler
lookup, and response packaging never touch `[io]`, `[net]`, or
`[time]`. Effects live at the transport boundary: the HTTP server
adapter in your `main()` function declares `[net, io, time]` and
calls into the pure core.

This matches lex-ocpp's split (`route` pure, `route_io` effectful)
and lex-web's split (`dispatch_pure` vs `dispatch`). It makes the
library fully testable without a transport, and lets users compose
the core with whatever transport / persistence layer they prefer.

The dispatcher's signature takes a `timestamp :: Str` argument
rather than reaching for `time.now_str()`: tests pass a fixed
timestamp for deterministic golden fixtures; production passes
`time.now_str()` from the transport adapter (the `[time]` effect
sits at the edge).

### Constraints as variants, not closures

OCPI enums (LocationType, ConnectorType, TokenType, SessionStatus,
CommandResult, …) are exposed as `fn name() -> Str` constants and
reflected at the validation boundary via lex-schema's
`StrOneOf(all_xxx())`. Three concrete payoffs over closure-based
validation:

1. **Inspectable by `lex audit`.** `lex audit --calls StrOneOf` lists
   every enum-bounded field in your codebase. Closures vanish.
2. **Codegen-friendly.** Pass any of these schemas to
   `lex-schema/sdk` and get TypeScript / Python / SQL DDL for free
   — the OCPI datatypes round-trip through the same pipeline as
   any other validated payload.
3. **Cheaper.** A variant is a tagged record; a closure carries
   captures plus an indirect call.

Extension is open: add a `StrOneOf(["MY_CUSTOM_TYPE"])` constraint
to your validator without forking lex-ocpi. The spec leaves room for
vendor extensions on most enums (Capability, ConnectorType, …), so a
closed Lex sum would be the wrong shape.

### Validators accumulate, not short-circuit

A malformed Location payload returns *every* failing field at once —
not the first one. This matches pydantic's `ValidationError` shape:
a UI rendering the response can highlight every failing field in a
single pass, not require N round-trips.

```
PropertyConstraintViolation {
  violations: [
    { path: "address", code: "min_len",
      message: "must be at least 1 characters" },
    { path: "coordinates.latitude", code: "max_len",
      message: "must be at most 10 characters" },
  ]
}
```

### One framework, three spec versions

OCPI 2.1.1 / 2.2.1 / 2.3.0 share the same wire-level envelope and
status code catalog; they differ on which modules exist and on the
exact shape of some objects (CDR field renames, Token shape, the
addition of Payments in 2.3.0). lex-ocpi:

- shares `src/envelope.lex`, `src/status.lex`, `src/headers.lex`,
  `src/route.lex`, `src/versions.lex`, `src/credentials.lex`,
  `src/pagination.lex`, `src/filters.lex`, `src/client.lex` between
  all three versions,
- exposes `src/v211/`, `src/v221/`, and `src/v230/` side by side,
- exposes the per-version role catalog (`role.all_roles_v211()`
  / `role.all_roles_v221()` / `role.all_roles_v230()`) so a single
  peer can advertise the right set per version.

Module-parity matrix vs `elumobility/ocpi-python`:

| Version | Modules | Parity |
|---------|---------|--------|
| 2.1.1   | enums + credentials + locations + sessions + tokens + cdrs + tariffs + commands | 8/8 |
| 2.2.1   | + chargingprofiles + hubclientinfo | 10/10 |
| 2.3.0   | + payments (new module), V2X / ISO 15118-20 enum widening, PTP role | 10/10 |

## Effect system

The pure path is fully effect-free; the HTTP-transport entry points
declare `[net, io, time]`:

| Function                                          | Effects |
|---------------------------------------------------|---------|
| `envelope.encode` / `envelope.parse`              | none |
| `route.dispatch`                                  | none (timestamp is an arg) |
| `headers.from_map` / `headers.to_map`             | none |
| `versions.detail_to_json`                         | none |
| `credentials.validate_credentials_v221`           | none |
| `v211/*.validate_*` / `v221/*` / `v230/*`         | none |
| `pagination.*` / `filters.*`                      | none |
| handler bodies (pure registry)                    | none |
| `route_io.dispatch`                               | `[io, time, sql]` |
| `client.send` / `client.get_with_token` / ...     | `[net]` |
| `client.handshake`                                | `[net]` |
| `examples/cpo_v221.main`                          | `[net, io, time]` |
| `examples/emsp_client.main`                       | `[net, io]` |

Pure modules + pure tests run without any `--allow-effects` flag.
Examples that drive an HTTP server / client need `net,io,time`.

## Follow-ups

- **Combined OCPP + OCPI worked example.** A CPO that terminates
  OCPP on one side and serves OCPI on the other — open at
  [#3](https://github.com/alpibrusl/lex-ocpi/issues/3). The two
  libraries compose today (lex-ocpp's `StartTransaction` handler
  writes a Session via lex-ocpi); the example would just wire them
  end-to-end.
- **Upstream lex-lang gaps** surfaced while building this library
  and tracked there: `?` / `try` sugar for `Result` / `Option`
  early-return ([lex-lang#435](https://github.com/alpibrusl/lex-lang/issues/435)),
  `std.net` middleware seam
  ([lex-lang#436](https://github.com/alpibrusl/lex-lang/issues/436)),
  match guard clauses
  ([lex-lang#438](https://github.com/alpibrusl/lex-lang/issues/438)),
  parametric record-alias coercion for `type Page[T] = { ... }`
  ([lex-lang#439](https://github.com/alpibrusl/lex-lang/issues/439)).
  None of these are blocking — they would let `pagination.lex`
  drop a few workarounds and let `client.lex` shorten its
  error-propagation chains.

## Pairing with lex-orm and lex-ocpp

OCPI CPO implementations almost always:

- persist Locations / EVSEs / Sessions / CDRs — pair with
  [lex-orm](https://github.com/alpibrusl/lex-orm) (typed query builder
  + migration runner on top of `std.sql`). Because OCPI payload
  schemas are `lex-schema` `ModelSchema` values, you can drive
  `lex-orm`'s `Repo[T]` off the same schema.
- drive their chargers over OCPP — pair with
  [lex-ocpp](https://github.com/alpibrusl/lex-ocpp). lex-ocpi
  consumes the *output* of lex-ocpp: when a `StartTransaction` lands
  on the OCPP side, the CPO writes a Session via lex-ocpi to the
  eMSP that owns the token used; when `StopTransaction` lands, the
  CPO emits a CDR.

A worked example combining both — a CPO that terminates OCPP on one
side and serves OCPI on the other — is open follow-up
([#3](https://github.com/alpibrusl/lex-ocpi/issues/3)).

## License

[EUPL-1.2](LICENSE) — to match the parent lex-lang ecosystem.
