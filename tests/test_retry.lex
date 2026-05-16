# lex-ocpi — Retry + backoff in client.lex (issue #8)
#
# Covers the pure surface of the retry layer in `src/client.lex`:
#
#   - Retry classifier — `is_retryable(err)` across every branch of
#     `ClientError` (HttpFailed / HttpStatus by code / BadEnvelope /
#     OcpiError) plus `is_retryable_status(code)` over the catalogue
#     the spec calls out (408 / 429 / 5xx retried; 4xx other don't).
#
#   - Retry-After header — `parse_retry_after_ms(headers)` for the
#     integer-seconds form, missing header, garbage value, negative
#     value, and the HTTP-date form (we don't parse the date — returns
#     None; documented in the source).
#
#   - `retry_after_hint(err)` — honoured only on HttpStatus(429|503),
#     None for every other shape.
#
#   - Backoff math — `scale_up(...)` and `exp_backoff_ms(attempt,
#     policy)` over the default policy and a couple of corner-case
#     policies (multiplier=100 ⇒ flat; max_delay reached early).
#
#   - `compute_backoff_ms(attempt, policy, hint)` — honour-vs-override
#     interaction between `respect_retry_after` and the supplied hint;
#     jitter on/off; clamp to max_delay; jitter ±20% lands inside
#     `[ms - 0.2·ms, ms + 0.2·ms]`. (Effect: `[time]`.)
#
#   - `reason_of(err)` — message rendering across every error variant.
#
# Live-loop tests (a fake HTTP target that 503s twice then 200s, etc.)
# are deferred to the conformance harness in issue #10. Everything the
# retry loop *does* is exercised here through the pure helpers it
# delegates to.

import "std.list" as list
import "std.map"  as map
import "std.str"  as str
import "std.time" as time

import "lex-schema/json_value" as jv

import "../src/client"   as client
import "../src/envelope" as env

# ---- Test plumbing ----------------------------------------------

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, int.to_str(want))
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, int.to_str(got)))
  }
}

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, want)
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, got))
  }
}

# ---- is_retryable ----------------------------------------------

fn test_retryable_transport() -> Result[Unit, Str] {
  assert_true(client.is_retryable(HttpFailed("connection refused")),
              "transport err must retry")
}

fn test_retryable_http_503() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 503, retry_after_ms: None })
  assert_true(client.is_retryable(err), "503 must retry")
}

fn test_retryable_http_429() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 429, retry_after_ms: Some(1000) })
  assert_true(client.is_retryable(err), "429 must retry")
}

fn test_retryable_http_408() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 408, retry_after_ms: None })
  assert_true(client.is_retryable(err), "408 must retry")
}

fn test_retryable_http_404_no() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 404, retry_after_ms: None })
  assert_true(client.is_retryable(err) == false, "404 must NOT retry")
}

fn test_retryable_http_401_no() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 401, retry_after_ms: None })
  assert_true(client.is_retryable(err) == false, "401 must NOT retry")
}

fn test_retryable_bad_envelope_no() -> Result[Unit, Str] {
  assert_true(client.is_retryable(BadEnvelope("garbage")) == false,
              "BadEnvelope must NOT retry")
}

fn test_retryable_ocpi_error_no() -> Result[Unit, Str] {
  let resp := { status_code: 2003,
                status_message: "Unknown Location",
                data: JNull,
                timestamp: "2026-05-16T00:00:00Z" }
  assert_true(client.is_retryable(OcpiError(resp)) == false,
              "OcpiError must NOT retry")
}

# ---- is_retryable_status edge cases ---------------------------

fn test_status_500() -> Result[Unit, Str] {
  assert_true(client.is_retryable_status(500), "500 retryable")
}

fn test_status_599() -> Result[Unit, Str] {
  assert_true(client.is_retryable_status(599), "599 retryable")
}

fn test_status_600_no() -> Result[Unit, Str] {
  # >= 600 is undefined territory; treat as non-retryable.
  assert_true(client.is_retryable_status(600) == false, "600 NOT retryable")
}

fn test_status_499_no() -> Result[Unit, Str] {
  assert_true(client.is_retryable_status(499) == false, "499 NOT retryable")
}

fn test_status_200_no() -> Result[Unit, Str] {
  assert_true(client.is_retryable_status(200) == false, "200 NOT retryable")
}

# ---- parse_retry_after_ms --------------------------------------

fn test_retry_after_integer_seconds() -> Result[Unit, Str] {
  let h := map.set(map.new(), "retry-after", "2")
  match client.parse_retry_after_ms(h) {
    Some(ms) => assert_eq_int(2000, ms, "2s → 2000ms"),
    None     => fail("expected Some(2000)"),
  }
}

fn test_retry_after_zero() -> Result[Unit, Str] {
  let h := map.set(map.new(), "retry-after", "0")
  match client.parse_retry_after_ms(h) {
    Some(ms) => assert_eq_int(0, ms, "0s → 0ms"),
    None     => fail("expected Some(0)"),
  }
}

fn test_retry_after_missing() -> Result[Unit, Str] {
  match client.parse_retry_after_ms(map.new()) {
    None    => pass(),
    Some(_) => fail("expected None when header absent"),
  }
}

fn test_retry_after_negative() -> Result[Unit, Str] {
  let h := map.set(map.new(), "retry-after", "-5")
  match client.parse_retry_after_ms(h) {
    None    => pass(),
    Some(_) => fail("negative seconds → None"),
  }
}

fn test_retry_after_garbage() -> Result[Unit, Str] {
  let h := map.set(map.new(), "retry-after", "soon")
  match client.parse_retry_after_ms(h) {
    None    => pass(),
    Some(_) => fail("non-integer value → None"),
  }
}

# HTTP-date form is documented as unsupported in src/client.lex —
# verifies the doc by exercising the unsupported branch.
fn test_retry_after_http_date_unsupported() -> Result[Unit, Str] {
  let h := map.set(map.new(), "retry-after",
                   "Wed, 21 Oct 2026 07:28:00 GMT")
  match client.parse_retry_after_ms(h) {
    None    => pass(),
    Some(_) => fail("HTTP-date form not parsed; should be None"),
  }
}

# ---- retry_after_hint -----------------------------------------

fn test_hint_on_503() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 503, retry_after_ms: Some(5000) })
  match client.retry_after_hint(err) {
    Some(ms) => assert_eq_int(5000, ms, "503 hint forwarded"),
    None     => fail("expected hint for 503"),
  }
}

fn test_hint_on_429() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 429, retry_after_ms: Some(3000) })
  match client.retry_after_hint(err) {
    Some(ms) => assert_eq_int(3000, ms, "429 hint forwarded"),
    None     => fail("expected hint for 429"),
  }
}

# Even on 5xx, hint is honoured only for 503 — not 500/502 etc.
# (Spec: Retry-After defined for 429/503/3xx; we don't promise to
# honour it on 500.)
fn test_hint_not_on_500() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 500, retry_after_ms: Some(9999) })
  match client.retry_after_hint(err) {
    None    => pass(),
    Some(_) => fail("hint suppressed for 500"),
  }
}

fn test_hint_not_on_transport() -> Result[Unit, Str] {
  match client.retry_after_hint(HttpFailed("nope")) {
    None    => pass(),
    Some(_) => fail("transport err has no hint"),
  }
}

# ---- Backoff math (pure) --------------------------------------

fn dflt() -> client.RetryPolicy { client.default_retry_policy() }

fn test_backoff_attempt_1() -> Result[Unit, Str] {
  assert_eq_int(200, client.exp_backoff_ms(1, dflt()),
                "attempt 1 = base")
}

fn test_backoff_attempt_2() -> Result[Unit, Str] {
  assert_eq_int(400, client.exp_backoff_ms(2, dflt()),
                "attempt 2 = 2× base")
}

fn test_backoff_attempt_3() -> Result[Unit, Str] {
  assert_eq_int(800, client.exp_backoff_ms(3, dflt()),
                "attempt 3 = 4× base")
}

# 200 × 2^9 = 102_400 — clamped to max_delay_ms (30_000).
fn test_backoff_caps_at_max() -> Result[Unit, Str] {
  assert_eq_int(30000, client.exp_backoff_ms(10, dflt()),
                "attempt 10 capped at max")
}

# multiplier_x100 = 100 ⇒ flat delay (no growth).
fn test_backoff_flat_policy() -> Result[Unit, Str] {
  let flat := { max_attempts: 5, initial_delay_ms: 100, max_delay_ms: 30000,
                multiplier_x100: 100, jitter: false, respect_retry_after: true }
  assert_eq_int(100, client.exp_backoff_ms(5, flat),
                "flat policy stays at base")
}

# 1.5× multiplier — integer-floor-friendly: 100 → 150 → 225 → 337
fn test_backoff_one_and_half() -> Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 100, max_delay_ms: 30000,
             multiplier_x100: 150, jitter: false, respect_retry_after: true }
  assert_eq_int(100, client.exp_backoff_ms(1, p), "attempt 1") and_ok
  assert_eq_int(150, client.exp_backoff_ms(2, p), "attempt 2") and_ok
  assert_eq_int(225, client.exp_backoff_ms(3, p), "attempt 3")
}

# Trivial `and_ok` chain so we can return on first failure.
fn and_ok(a :: Result[Unit, Str], b :: Result[Unit, Str]) -> Result[Unit, Str] {
  match a { Err(_) => a, Ok(_) => b }
}

# ---- compute_backoff_ms (interaction with hint + jitter) ------

fn test_compute_honours_retry_after() -> [time] Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 200, max_delay_ms: 30000,
             multiplier_x100: 200, jitter: false, respect_retry_after: true }
  let got := client.compute_backoff_ms(1, p, Some(5000))
  assert_eq_int(5000, got, "Retry-After honoured")
}

fn test_compute_caps_retry_after() -> [time] Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 200, max_delay_ms: 1000,
             multiplier_x100: 200, jitter: false, respect_retry_after: true }
  let got := client.compute_backoff_ms(1, p, Some(99999))
  assert_eq_int(1000, got, "Retry-After capped to max_delay_ms")
}

fn test_compute_ignores_retry_after_when_off() -> [time] Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 200, max_delay_ms: 30000,
             multiplier_x100: 200, jitter: false, respect_retry_after: false }
  let got := client.compute_backoff_ms(1, p, Some(5000))
  assert_eq_int(200, got, "exponential when respect_retry_after=false")
}

fn test_compute_no_hint_uses_exp() -> [time] Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 200, max_delay_ms: 30000,
             multiplier_x100: 200, jitter: false, respect_retry_after: true }
  let got := client.compute_backoff_ms(3, p, None)
  assert_eq_int(800, got, "no hint → exponential")
}

# Jitter ON: result lands in [ms - 20%, ms + 20%].
fn test_compute_jitter_in_range() -> [time] Result[Unit, Str] {
  let p := { max_attempts: 5, initial_delay_ms: 1000, max_delay_ms: 30000,
             multiplier_x100: 100, jitter: true, respect_retry_after: true }
  let got := client.compute_backoff_ms(1, p, None)
  # base = 1000, spread = 200, valid range [800, 1200].
  if got >= 800 and got <= 1200 { pass() }
  else { fail(str.concat("jittered value out of [800,1200]: ",
                          int.to_str(got))) }
}

# ---- reason_of -------------------------------------------------

fn test_reason_transport() -> Result[Unit, Str] {
  assert_eq_str("transport: refused",
                client.reason_of(HttpFailed("refused")),
                "transport reason")
}

fn test_reason_http_status() -> Result[Unit, Str] {
  let err := HttpStatus({ code: 503, retry_after_ms: None })
  assert_eq_str("http-503", client.reason_of(err), "http status reason")
}

fn test_reason_bad_envelope() -> Result[Unit, Str] {
  assert_eq_str("bad-envelope: nope",
                client.reason_of(BadEnvelope("nope")),
                "bad envelope reason")
}

fn test_reason_ocpi_error() -> Result[Unit, Str] {
  let resp := { status_code: 2003,
                status_message: "Unknown Location",
                data: JNull,
                timestamp: "2026-05-16T00:00:00Z" }
  assert_eq_str("ocpi-error", client.reason_of(OcpiError(resp)),
                "ocpi reason")
}

# ---- Policy constructors --------------------------------------

fn test_default_policy_shape() -> Result[Unit, Str] {
  let p := client.default_retry_policy()
  if p.max_attempts == 5 and p.initial_delay_ms == 200
     and p.max_delay_ms == 30000 and p.multiplier_x100 == 200
     and p.jitter == true and p.respect_retry_after == true {
    pass()
  } else {
    fail("default_retry_policy values drifted")
  }
}

fn test_no_retry_policy_shape() -> Result[Unit, Str] {
  let p := client.no_retry_policy()
  assert_eq_int(1, p.max_attempts, "no_retry max_attempts")
}

# ---- Suite + runner -------------------------------------------

fn pure_suite() -> List[Result[Unit, Str]] {
  [
    # Classifier
    test_retryable_transport(),
    test_retryable_http_503(),
    test_retryable_http_429(),
    test_retryable_http_408(),
    test_retryable_http_404_no(),
    test_retryable_http_401_no(),
    test_retryable_bad_envelope_no(),
    test_retryable_ocpi_error_no(),
    # Status codes
    test_status_500(),
    test_status_599(),
    test_status_600_no(),
    test_status_499_no(),
    test_status_200_no(),
    # Retry-After header
    test_retry_after_integer_seconds(),
    test_retry_after_zero(),
    test_retry_after_missing(),
    test_retry_after_negative(),
    test_retry_after_garbage(),
    test_retry_after_http_date_unsupported(),
    # retry_after_hint
    test_hint_on_503(),
    test_hint_on_429(),
    test_hint_not_on_500(),
    test_hint_not_on_transport(),
    # Backoff math
    test_backoff_attempt_1(),
    test_backoff_attempt_2(),
    test_backoff_attempt_3(),
    test_backoff_caps_at_max(),
    test_backoff_flat_policy(),
    test_backoff_one_and_half(),
    # reason_of
    test_reason_transport(),
    test_reason_http_status(),
    test_reason_bad_envelope(),
    test_reason_ocpi_error(),
    # Policy constructors
    test_default_policy_shape(),
    test_no_retry_policy_shape(),
  ]
}

fn time_suite() -> [time] List[Result[Unit, Str]] {
  [
    test_compute_honours_retry_after(),
    test_compute_caps_retry_after(),
    test_compute_ignores_retry_after_when_off(),
    test_compute_no_hint_uses_exp(),
    test_compute_jitter_in_range(),
  ]
}

fn count_failures(rs :: List[Result[Unit, Str]]) -> Int {
  list.fold(rs, 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}

fn run_all() -> [time] Int {
  count_failures(pure_suite()) + count_failures(time_suite())
}
