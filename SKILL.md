# lex-ocpi — agent skill manifest

Agentic discovery surface for `lex-ocpi`, an OCPI (Open Charge Point
Interface) library written in Lex. An LLM agent that needs to emit
OCPI-compliant code in this codebase should consume this file before
generating; every claim here is grounded in a Lex function with a
stable `SigId` (queryable via `lex blame --with-evidence`).

Format follows the [agentskills.io](https://agentskills.io) convention.

## When to use this library

Reach for `lex-ocpi` whenever you're emitting code that:

- Constructs the wire envelope an OCPI peer sends (`data` / `status_code` /
  `status_message` / `timestamp`).
- Parses or builds the eight OCPI HTTP request headers (`Authorization`,
  `X-Request-ID`, `X-Correlation-ID`, plus the four
  `OCPI-from/to-{country-code,party-id}`).
- Validates an inbound JSON payload against an OCPI 2.2.1 object schema
  (Location, EVSE, Connector, Session, CDR, Token, Tariff, Command, etc).
- Dispatches OCPI HTTP requests through a handler registry.
- Generates a `ModelSchema` value from an OCA-published JSON Schema doc.

Don't reach for it when you're handling:

- **CP↔CSMS WebSocket traffic.** Use [`lex-ocpp`](https://github.com/alpibrusl/lex-ocpp) instead.
- **Free-form HTTP routing.** Pair `lex-web` with this library — the
  OCPI dispatcher is opinionated about `(method, module)` keys.
- **Tarriff display / billing.** OCPI Tariffs carry pricing data but
  not billing engine state — that's downstream.

## Core entry points

### Envelope (`lex-ocpi/envelope`)

| Function | Use |
|---|---|
| `env.ok(data, timestamp)` | success with payload |
| `env.ok_list(items, timestamp)` | success with array payload |
| `env.ok_empty(timestamp)` | success, no payload (idempotent POST) |
| `env.fail(code, message, timestamp)` | error envelope, omit `data` |
| `env.fail_with_data(code, message, data, timestamp)` | error envelope with structured detail |
| `env.encode(r)` | OcpiResponse → wire JSON |
| `env.parse(raw)` | wire JSON → OcpiResponse (Result) |
| `env.is_success` / `is_client_error` / `is_server_error` / `is_hub_error` | code-range predicates |

### Status codes (`lex-ocpi/status`)

Wire-exact code constants — **never inline the integer** at a call site:

- `status.success()` → 1000
- `status.invalid_or_missing_parameters()` → 2001
- `status.unknown_location()` → 2003
- `status.unknown_token()` → 2004
- `status.server_error()` → 3000
- `status.unsupported_version()` → 3002
- `status.unknown_receiver()` → 4002
- `status.connection_problem()` → 4004
- ...

`status.to_message(code)` maps any known code to its canonical
human-readable string (returns `""` for unknown codes so the
envelope encoder can omit `status_message`).

### Headers (`lex-ocpi/headers`)

```lex
import "lex-ocpi/headers" as h

# Parse from std.net's Request.headers
let parsed := h.from_map(req.headers)

# Build for outbound HTTP request
let m := h.to_map(h.new(
  authorization,   # "Token <b64>"
  request_id,      # X-Request-ID
  correlation_id,  # X-Correlation-ID
  from_party,      # party.PartyId
  to_party))       # party.PartyId

# Strip the "Token " prefix to extract the credentials B64
let token_b64 := h.strip_token_prefix(parsed.authorization)
```

### Roles (`lex-ocpi/role`)

`role.cpo()` / `role.emsp()` / `role.hub()` / `role.nsp()` /
`role.other()` / `role.scsp()` / `role.ptp()` — wire strings.

`role.all_roles_v221()` returns the v2.2.1 catalog (no PTP);
`role.all_roles_v230()` adds PTP for v2.3.0.

### Module identifiers (`lex-ocpi/module_id`)

`mid.versions()` / `mid.credentials()` / `mid.cdrs()` /
`mid.chargingprofiles()` / `mid.commands()` / `mid.hubclientinfo()` /
`mid.locations()` / `mid.sessions()` / `mid.tariffs()` / `mid.tokens()` /
`mid.payments()` (v2.3.0).

`mid.all_v211()` / `mid.all_v221()` / `mid.all_v230()` for the
per-version catalog.

### Route registry (`lex-ocpi/route`)

```lex
import "lex-ocpi/route"      as route
import "lex-ocpi/module_id"  as mid
import "lex-ocpi/v221/tokens" as tokens

# Pure handler: OcpiRequest → HandlerResult
fn on_put_token(req :: route.OcpiRequest) -> route.HandlerResult {
  # … process the validated body …
  route.ok_empty()
}

# Register routes (validator runs BEFORE the handler)
fn registry() -> route.Registry {
  route.new()
    |> fn (r :: route.Registry) -> route.Registry {
         route.handler_with_schema(r, route.put(), mid.tokens(),
           tokens.validate_token, on_put_token)
       }
}

# Pure dispatch (timestamp is an arg so the core is effect-free)
fn handle(req :: route.OcpiRequest, now :: Str) -> env.OcpiResponse {
  route.dispatch(registry(), req, now)
}
```

`HandlerResult` is `HOk(jv.Json) | HOkList(List[jv.Json]) | HOkEmpty | HErr(OcpiError)`.
The convenience builders are `route.ok` / `route.ok_list` /
`route.ok_empty` / `route.fail` / `route.fail_with`.

### Errors (`lex-ocpi/error`)

Specific-error constructors that pre-fill the right OCPI status code:

| Helper | Status | Use |
|---|---|---|
| `oe.invalid_parameters(msg)` | 2001 | malformed inbound payload |
| `oe.unknown_location(id)`    | 2003 | requested LOC doesn't exist |
| `oe.unknown_token(uid)`      | 2004 | requested token doesn't exist |
| `oe.server_error(msg)`       | 3000 | internal failure |
| `oe.unsupported_version(v)`  | 3002 | client asked for a version we don't speak |
| `oe.from_schema_errors(es)`  | 2001 | adapt a `lex-schema` validation error list |

### Versions module (`lex-ocpi/versions`)

```lex
# Build the /ocpi/versions list
versions.version(versions.v221(), "https://cpo.example.com/ocpi/2.2.1")
  |> versions.version_to_json

# Build the /ocpi/2.2.1/ endpoint catalogue
versions.detail(versions.v221(),
  versions.standard_cpo_v221_endpoints("https://cpo.example.com/ocpi/2.2.1"))
  |> versions.detail_to_json
```

`versions.standard_cpo_v221_endpoints(base)` and
`versions.standard_emsp_v221_endpoints(base)` ship the canonical
7-endpoint set per role.

### Credentials module (`lex-ocpi/credentials`)

```lex
import "lex-ocpi/credentials" as creds

# Build a Credentials value
let c := creds.new(token_b64, versions_url, [
  creds.credentials_role(role.cpo(),
    creds.business_details("ExampleCPO"),
    "EXM", "NL"),
])

# Validate an inbound Credentials POST body
match creds.validate_credentials_v221(body) {
  Err(es) => respond_with(oe.from_schema_errors(es)),
  Ok(_)   => # … swap tokens, store the peer's endpoint catalog …
}
```

## OCPI 2.2.1 module surface (`lex-ocpi/v221/*`)

Every module ships:
- A `ModelSchema` value (declarative; codegen-friendly).
- A `validate_<object>(j) -> Result[jv.Json, List[e.Error]]` wrapper
  that delegates to `lex-schema`'s `s.validate`.

| Module | Schemas |
|---|---|
| `v221/locations` | `Location`, `EVSE`, `Connector`, `GeoLocation`, `Image`, `BusinessDetails`, `DisplayText`, `StatusSchedule`, `AdditionalGeoLocation` |
| `v221/sessions`  | `Session`, `CdrToken`, `CdrDimension`, `ChargingPeriod`, `Price`, `ChargingPreferences` |
| `v221/cdrs`      | `CDR`, `CdrLocation`, `SignedData`, `SignedValue` (`stub_tariff_ref` for embedded refs) |
| `v221/tokens`    | `Token`, `EnergyContract`, `LocationReferences`, `AuthorizationInfo`, `DisplayText` |
| `v221/tariffs`   | `Tariff`, `TariffElement`, `PriceComponent`, `TariffRestrictions`, `EnergyMix`, `EnergySource`, `EnvironmentalImpact` |
| `v221/commands`  | `CommandResponse`, `CommandResult`, `StartSession`, `StopSession`, `ReserveNow`, `CancelReservation`, `UnlockConnector`, `DisplayText` |
| `v221/chargingprofiles` | `ChargingProfile`, `ChargingProfilePeriod`, `ActiveChargingProfile`, `SetChargingProfile`, `ChargingProfileResponse`, `ActiveChargingProfileResult`, `ChargingProfileResult` |
| `v221/hubclientinfo` | `ClientInfo` |
| `v221/enums`     | LocationType, ParkingType, EVSE Status, Capability, ConnectorType, ConnectorFormat, PowerType, TokenType, WhitelistType, AllowedType, SessionStatus, AuthMethod, CdrDimensionType, TariffDimensionType, TariffType, CommandType, CommandResponseType, CommandResult, ReservationStatus, DayOfWeek (all `fn <name>() -> Str` + `all_<enum>() -> List[Str]`) |

Pattern for emitting a validated handler:

```lex
import "lex-ocpi/route"          as route
import "lex-ocpi/module_id"      as mid
import "lex-ocpi/v221/sessions"  as sess

fn on_put_session(_req :: route.OcpiRequest) -> route.HandlerResult {
  route.ok_empty()
}

fn registry() -> route.Registry {
  route.new()
    |> fn (r :: route.Registry) -> route.Registry {
         route.handler_with_schema(r, route.put(), mid.sessions(),
           sess.validate_session, on_put_session)
       }
}
```

## Codegen tool (`tools/gen.lex`)

Bulk-import an OCA-published JSON Schema doc as a Lex `ModelSchema`
+ validator:

```sh
lex run tools/gen.lex generate "$(cat path/to/schema.json | jq -R -s .)"
```

The output is a Lex source fragment — review, then paste into the
matching `src/vXX/<module>.lex`. Coverage: top-level `type: object`
schemas with primitives, arrays, enums, string-length constraints,
int `minimum`. Open follow-ups: `$ref`, `oneOf`, `pattern`, `format`.

## Cross-cutting conventions

- **Pure core, effect edge.** Everything under `src/` is pure. The
  dispatcher takes an explicit `timestamp :: Str` arg so the pure
  core can be exercised from tests without `[time]`; the transport
  adapter in your `main()` supplies `time.now_str()`.
- **Variant strings via `fn () -> Str` constants.** Never inline an
  OCPI status code / module identifier / enum member at a call site
  — use the constant. `lex audit --calls StrOneOf` lists every
  enum-bounded field automatically.
- **`examples {}` blocks on every pure fn.** Folded into the SigId;
  run at `lex check` time. When emitting code that depends on a
  function from this library, the `examples {}` block is the
  ground truth for its shape.

## Discoverability via ACLI

Every fn in this library is queryable via `lex --output json check
<file>` (gives you typed AST + signatures), `lex blame <fn>
--with-evidence` (shows the attestation chain), and `lex audit
--calls <fn>` (every caller of a given API). For LLM-driven code
authoring against this library, prefer those over grep.

## Version

`lex.toml` pins `lex = "0.9.4"`. Library version is `0.1.0` —
see `README.md` for the deferred-work tracker.
