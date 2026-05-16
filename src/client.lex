# lex-ocpi — outbound HTTP client
#
# A CPO that wants to push Sessions/CDRs/Locations to its eMSPs, or
# an eMSP that runs the Credentials handshake against a CPO, calls
# out HTTP. This module bundles `std.http` with the OCPI envelope
# decode + header build pattern so callers don't repeat that
# boilerplate at every call site.
#
# Effects: `[net]` (wire ops only). Pure builders for assembling
# the request — see `with_party_routing`, `with_token`, etc.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.1 (Response Object — decode contract)
#   OCPI 2.2.1 — Part I §4.2 (Request Headers — `Token <b64>`)

import "std.str"   as str
import "std.list"  as list
import "std.map"   as map
import "std.http"  as http
import "std.bytes" as bytes
import "std.time"  as time
import "std.int"   as int

import "lex-schema/json_value" as jv

import "./envelope" as env
import "./headers"  as h
import "./party"    as party

# ---- HttpError envelope (lifted into our error type) ------------

type ClientError =
    HttpFailed(Str)                            # underlying net error (DNS, connection refused, ...)
  | HttpStatus({ code :: Int,                  # 4xx / 5xx HTTP response (NOT an OCPI envelope)
                 retry_after_ms :: Option[Int] })
  | BadEnvelope(Str)                            # could not decode OCPI envelope
  | OcpiError(env.OcpiResponse)                 # decoded envelope carrying status_code >= 2000

# ---- Request builders -------------------------------------------
#
# Build a vanilla `HttpRequest` (the std.http record shape) with the
# OCPI eight-headers preloaded. The returned value is a plain
# `HttpRequest` so callers can stack `http.with_header` /
# `http.with_timeout_ms` on top.

fn base_request(method :: Str, url :: Str) -> HttpRequest {
  {
    method:     method,
    url:        url,
    headers:    map.new(),
    body:       None,
    timeout_ms: Some(30000),
  }
}

fn with_token(req :: HttpRequest, token_b64 :: Str) -> HttpRequest {
  http.with_header(req, h.h_authorization(),
    str.concat("Token ", token_b64))
}

fn with_request_id(req :: HttpRequest, request_id :: Str) -> HttpRequest {
  http.with_header(req, h.h_request_id(), request_id)
}

fn with_correlation_id(req :: HttpRequest, correlation_id :: Str) -> HttpRequest {
  http.with_header(req, h.h_correlation_id(), correlation_id)
}

fn with_party_routing(
  req        :: HttpRequest,
  from_party :: party.PartyId,
  to_party   :: party.PartyId
) -> HttpRequest {
  let r1 := http.with_header(req, h.h_from_country_code(), from_party.country_code)
  let r2 := http.with_header(r1,  h.h_from_party_id(),     from_party.party_id)
  let r3 := http.with_header(r2,  h.h_to_country_code(),   to_party.country_code)
  http.with_header(r3,            h.h_to_party_id(),       to_party.party_id)
}

# Attach an OCPI JSON body. The body is encoded inline; callers
# building a payload from a `jv.Json` value pass `jv.stringify(...)`.
fn with_json_body(req :: HttpRequest, body :: Str) -> HttpRequest {
  let with_ct := http.with_header(req, "content-type", "application/json")
  {
    method:     with_ct.method,
    url:        with_ct.url,
    headers:    with_ct.headers,
    body:       Some(bytes.from_str(body)),
    timeout_ms: with_ct.timeout_ms,
  }
}

# ---- Send + decode ----------------------------------------------
#
# Run the request through `http.send`, decode the response body
# into an `OcpiResponse` envelope, and lift transport / decode /
# OCPI-error states into a single `ClientError` ADT. A 1xxx envelope
# returns `Ok(envelope.data)`; a 2xxx/3xxx/4xxx envelope returns
# `Err(OcpiError(envelope))` so callers can read `status_code` /
# `status_message` / `data` for the failure detail.

fn send(req :: HttpRequest) -> [net] Result[jv.Json, ClientError] {
  match http.send(req) {
    Err(_)   => Err(HttpFailed("http.send transport error")),
    Ok(resp) => if resp.status >= 200 and resp.status < 300 {
                  decode_body(resp.body)
                } else {
                  Err(HttpStatus({
                    code: resp.status,
                    retry_after_ms: parse_retry_after_ms(resp.headers),
                  }))
                },
  }
}

fn decode_body(raw :: Bytes) -> Result[jv.Json, ClientError] {
  match bytes.to_str(raw) {
    Err(e) => Err(BadEnvelope(str.concat("response body not UTF-8: ", e))),
    Ok(s)  => match env.parse(s) {
      Err(ee) => Err(BadEnvelope(ee.message)),
      Ok(r)   => if r.status_code >= 1000 and r.status_code < 2000 {
        Ok(r.data)
      } else {
        Err(OcpiError(r))
      },
    },
  }
}

# Pull `Retry-After` (seconds) out of a response header map. The
# spec also allows an HTTP-date form (`Wed, 21 Oct 2026 07:28:00
# GMT`); parsing that takes a real date parser and is deferred —
# in practice almost every peer ships the integer-seconds form.
# Header name is lowercased to match `std.http`'s canonical map.

fn parse_retry_after_ms(headers :: Map[Str, Str]) -> Option[Int]
  examples {
    parse_retry_after_ms(map.set(map.new(), "retry-after", "2")) => Some(2000),
    parse_retry_after_ms(map.new())                              => None,
  }
{
  match map.get(headers, "retry-after") {
    None    => None,
    Some(s) => match str.to_int(s) {
      None    => None,                          # date-form or garbage — caller fallback
      Some(n) => if n >= 0 { Some(n * 1000) } else { None },
    },
  }
}

# ---- Convenience: GET with auth ---------------------------------
#
# Most OCPI reads are a single GET against a versions / locations /
# tariffs URL with the credentials token attached. `get_with_token`
# packages the common shape; callers stack `with_party_routing` /
# `with_request_id` on the returned request when needed.

fn get_with_token(url :: Str, token_b64 :: Str) -> [net] Result[jv.Json, ClientError] {
  let req := with_token(base_request("GET", url), token_b64)
  send(req)
}

# ---- Convenience: PUT a JSON body -------------------------------

fn put_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("PUT", url), token_b64),
              body)
  send(req)
}

fn post_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("POST", url), token_b64),
              body)
  send(req)
}

fn patch_json(
  url       :: Str,
  body      :: Str,
  token_b64 :: Str
) -> [net] Result[jv.Json, ClientError] {
  let req := with_json_body(
              with_token(base_request("PATCH", url), token_b64),
              body)
  send(req)
}

fn delete_with_token(url :: Str, token_b64 :: Str) -> [net] Result[jv.Json, ClientError] {
  let req := with_token(base_request("DELETE", url), token_b64)
  send(req)
}

# ---- Retry policy + classifier ---------------------------------
#
# OCPI peers are expected to retry transient failures rather than
# bubble them up. `RetryPolicy` is the knob: exponential backoff
# capped at `max_delay_ms`, optional jitter (±20%), and an honor-
# `Retry-After` switch for 429 / 503 responses.
#
# The classifier `is_retryable(err)` decides per-error:
#
#   * transport failure (DNS, connection refused, timeout)         retry
#   * HTTP 408 / 429 / 5xx                                         retry
#   * HTTP 4xx (other) — caller bug, retrying won't help          give up
#   * `BadEnvelope` — JSON parse / shape failure                   give up
#   * `OcpiError` — peer answered with status_code ≥ 2000          give up
#     (the OCPI envelope is the *answer*; the peer isn't broken,
#     the request just lost. A 4-04 `Unknown Location` will never
#     turn into a 2-00 `Success` by retrying.)
#
# `RetryPolicy` carries the multiplier as `multiplier_x100`
# (integer × 100) to avoid Float math — 200 = 2.0×, 150 = 1.5×.
# Multiplier values below 100 (sub-linear backoff) are allowed but
# unusual; 100 produces fixed-delay retries.

type RetryPolicy = {
  max_attempts        :: Int,
  initial_delay_ms    :: Int,
  max_delay_ms        :: Int,
  multiplier_x100     :: Int,
  jitter              :: Bool,
  respect_retry_after :: Bool,
}

fn default_retry_policy() -> RetryPolicy {
  {
    max_attempts:        5,
    initial_delay_ms:    200,
    max_delay_ms:        30000,
    multiplier_x100:     200,           # 2.0×
    jitter:              true,
    respect_retry_after: true,
  }
}

# One-shot policy. Useful for tests and for callers that need
# explicitly-no-retry semantics.
fn no_retry_policy() -> RetryPolicy {
  { max_attempts: 1, initial_delay_ms: 0, max_delay_ms: 0,
    multiplier_x100: 100, jitter: false, respect_retry_after: false }
}

fn is_retryable(e :: ClientError) -> Bool
  examples {
    is_retryable(HttpFailed("connection refused"))            => true,
    is_retryable(HttpStatus({ code: 503, retry_after_ms: None })) => true,
    is_retryable(HttpStatus({ code: 429, retry_after_ms: None })) => true,
    is_retryable(HttpStatus({ code: 408, retry_after_ms: None })) => true,
    is_retryable(HttpStatus({ code: 404, retry_after_ms: None })) => false,
    is_retryable(HttpStatus({ code: 401, retry_after_ms: None })) => false,
    is_retryable(BadEnvelope("garbage"))                       => false,
  }
{
  match e {
    HttpFailed(_)    => true,
    HttpStatus(info) => is_retryable_status(info.code),
    BadEnvelope(_)   => false,
    OcpiError(_)     => false,
  }
}

fn is_retryable_status(code :: Int) -> Bool
  examples {
    is_retryable_status(408) => true,
    is_retryable_status(429) => true,
    is_retryable_status(500) => true,
    is_retryable_status(502) => true,
    is_retryable_status(503) => true,
    is_retryable_status(599) => true,
    is_retryable_status(404) => false,
    is_retryable_status(200) => false,
    is_retryable_status(400) => false,
    is_retryable_status(401) => false,
    is_retryable_status(403) => false,
  }
{
  if code == 408 { true }
  else { if code == 429 { true }
  else { if code >= 500 and code < 600 { true }
  else { false } } }
}

# Extract the Retry-After hint (ms) from an error, if any. Honoured
# only for HttpStatus(429|503); the spec defines Retry-After for
# those two codes and 3xx redirects, but 3xx isn't on the retry
# list anyway.
fn retry_after_hint(e :: ClientError) -> Option[Int] {
  match e {
    HttpStatus(info) => match info.code {
      429 => info.retry_after_ms,
      503 => info.retry_after_ms,
      _   => None,
    },
    HttpFailed(_)    => None,
    BadEnvelope(_)   => None,
    OcpiError(_)     => None,
  }
}

# ---- Backoff math (pure) ---------------------------------------
#
# Exponential backoff `base * multiplier^(attempt-1)`, capped at
# `max_delay_ms`. Jitter, when on, is applied by the caller (it
# needs `[time]` to seed; see `compute_backoff_ms` below).
#
# Integer math throughout: `multiplier_x100 / 100` per step. The
# accumulator is bounded by `max_delay_ms` so overflow on long
# attempt counts is not a concern.

fn exp_backoff_ms(attempt :: Int, policy :: RetryPolicy) -> Int
  examples {
    # default policy: 200ms base, 2.0×, 30000ms cap
    exp_backoff_ms(1, default_retry_policy()) => 200,
    exp_backoff_ms(2, default_retry_policy()) => 400,
    exp_backoff_ms(3, default_retry_policy()) => 800,
    exp_backoff_ms(4, default_retry_policy()) => 1600,
    # cap kicks in eventually — attempt 10 would be 200 * 2^9 = 102400, clamped
    exp_backoff_ms(10, default_retry_policy()) => 30000,
  }
{
  let raw := scale_up(policy.initial_delay_ms, policy.multiplier_x100,
                      attempt - 1, policy.max_delay_ms)
  min_i(raw, policy.max_delay_ms)
}

# Recursive integer scale-up. Bounded by `cap` to avoid the
# accumulator running away on long chains (and incidentally avoid
# Int overflow).
fn scale_up(acc :: Int, mult_x100 :: Int, n :: Int, cap :: Int) -> Int {
  if n <= 0 { acc }
  else { if acc >= cap { cap }
  else { scale_up(acc * mult_x100 / 100, mult_x100, n - 1, cap) } }
}

fn min_i(a :: Int, b :: Int) -> Int {
  if a < b { a } else { b }
}

# ±20% jitter using `time.mono_ns()` as the entropy source. We can't
# use `rand.int_in` because the runtime stub returns the midpoint,
# making jitter a no-op; the monotonic clock gives real spread
# between processes (and run-to-run within a single process) without
# requiring the `[rand]` effect.
fn apply_jitter_ms(ms :: Int) -> [time] Int {
  let spread := ms * 20 / 100
  if spread == 0 { ms } else {
    let offset := time.mono_ns() % (2 * spread + 1)
    ms - spread + offset
  }
}

# Compose the per-attempt delay: honour Retry-After when present
# and policy.respect_retry_after is on, otherwise fall back to
# exponential backoff. Final value is jittered (when policy.jitter)
# and clamped to `max_delay_ms`.

fn compute_backoff_ms(
  attempt :: Int,
  policy  :: RetryPolicy,
  hint    :: Option[Int]
) -> [time] Int {
  let base := match hint {
    Some(ra) => if policy.respect_retry_after {
                  min_i(ra, policy.max_delay_ms)
                } else {
                  exp_backoff_ms(attempt, policy)
                },
    None    => exp_backoff_ms(attempt, policy),
  }
  if policy.jitter { apply_jitter_ms(base) } else { base }
}

# ---- Retry events ----------------------------------------------

type RetryEvent =
    Attempt({ n :: Int, delay_ms :: Int, reason :: Str })
  | GaveUp({ attempts :: Int, last_error :: ClientError })

fn reason_of(e :: ClientError) -> Str {
  match e {
    HttpFailed(m)    => str.concat("transport: ", m),
    HttpStatus(info) => str.concat("http-", int.to_str(info.code)),
    BadEnvelope(m)   => str.concat("bad-envelope: ", m),
    OcpiError(_)     => "ocpi-error",
  }
}

# ---- Retry loop ------------------------------------------------
#
# `send_with_retry(req, policy)` is the everyday helper — no
# observability, no [io]. The recursive loop ticks `attempt`
# (1-based) and `last_err` so the GaveUp path has the final-error
# detail. Each iteration:
#
#   1. send the request
#   2. on Ok: return it
#   3. on Err & not retryable: return Err (caller bug — no retry)
#   4. on Err & retryable & attempt >= max_attempts: return Err
#   5. on Err & retryable: compute delay → sleep → recur
#
# Termination is bounded by `max_attempts`; the helper never sleeps
# more than `max_delay_ms` per attempt (modulo a Retry-After
# instruction the peer sent, which is also capped). `time.sleep_ms`
# is itself capped at 60_000 by the runtime — anything beyond that
# is silently clamped.

fn send_with_retry(
  req    :: HttpRequest,
  policy :: RetryPolicy
) -> [net, time] Result[jv.Json, ClientError] {
  retry_loop(req, policy, 1)
}

fn retry_loop(
  req     :: HttpRequest,
  policy  :: RetryPolicy,
  attempt :: Int
) -> [net, time] Result[jv.Json, ClientError] {
  match send(req) {
    Ok(j)   => Ok(j),
    Err(e)  => if (is_retryable(e) == false) or attempt >= policy.max_attempts {
                 Err(e)
               } else {
                 let delay := compute_backoff_ms(attempt, policy,
                                                 retry_after_hint(e))
                 let _ := time.sleep_ms(delay)
                 retry_loop(req, policy, attempt + 1)
               },
  }
}

# Observable variant. The observer fires once per failed attempt
# with the upcoming sleep duration, and once at the final-give-up
# moment with the last error. Successful attempts emit no events
# (the Ok return IS the success signal).
#
# The observer signature is hardcoded `[io]`, which covers
# logging / stdout / file writes — the common observability shapes.
# Callers that need a different effect (actor tell, metrics
# counter) wrap their callback in an `[io]` no-op shim.

fn send_with_events(
  req      :: HttpRequest,
  policy   :: RetryPolicy,
  observer :: (RetryEvent) -> [io] Unit
) -> [net, time, io] Result[jv.Json, ClientError] {
  retry_loop_events(req, policy, observer, 1)
}

fn retry_loop_events(
  req      :: HttpRequest,
  policy   :: RetryPolicy,
  observer :: (RetryEvent) -> [io] Unit,
  attempt  :: Int
) -> [net, time, io] Result[jv.Json, ClientError] {
  match send(req) {
    Ok(j)   => Ok(j),
    Err(e)  => if (is_retryable(e) == false) or attempt >= policy.max_attempts {
                 let _ := observer(GaveUp({ attempts: attempt, last_error: e }))
                 Err(e)
               } else {
                 let delay := compute_backoff_ms(attempt, policy,
                                                 retry_after_hint(e))
                 let _ := observer(Attempt({
                   n: attempt + 1, delay_ms: delay, reason: reason_of(e),
                 }))
                 let _ := time.sleep_ms(delay)
                 retry_loop_events(req, policy, observer, attempt + 1)
               },
  }
}

# ---- Credentials handshake --------------------------------------
#
# The two-step OCPI registration:
#
#   1. GET <peer>/versions          → version list
#   2. GET <peer>/<version>/        → endpoint catalogue
#   3. POST <peer>/credentials      → swap our credentials for theirs
#
# We don't do retry / backoff — those belong at the caller's
# discretion. Failures surface as `ClientError` so the caller can
# inspect `OcpiError.r.status_code` to distinguish a `3002 unsupported
# version` from a `2000 wrong token` etc.
#
# Returns the peer's `Credentials` JSON value on success.

fn handshake(
  peer_versions_url :: Str,
  our_token         :: Str,
  our_credentials   :: jv.Json
) -> [net] Result[jv.Json, ClientError] {
  match get_with_token(peer_versions_url, our_token) {
    Err(e)  => Err(e),
    Ok(_versions) => {
      let creds_url := str.concat(
        derive_credentials_url(peer_versions_url),
        "/credentials")
      post_json(creds_url, jv.stringify(our_credentials), our_token)
    },
  }
}

# Best-effort derivation: strip the trailing `/versions` from the
# peer's discovery URL to recover the version-prefix. Real OCPI flows
# pick a specific version from the `data` array first; this helper is
# the bottom-of-the-stack case where you just want the "latest" path.
fn derive_credentials_url(versions_url :: Str) -> Str {
  match str.strip_suffix(versions_url, "/versions") {
    None     => versions_url,
    Some(p)  => p,
  }
}
