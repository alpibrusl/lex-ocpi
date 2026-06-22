# lex-ocpi — Idempotency cache tests (issue #7)
#
# Covers `src/idempotency.lex`. The cache splits into three layers
# and each tests at its own effect level:
#
#   * **Pure transition fn (`cache_handler`)** — covered exhaustively
#     by feeding state + message through the handler and inspecting
#     state/reply. No `[concurrent]`. This is where the LRU + TTL +
#     in-flight invariants live.
#
#   * **Actor end-to-end** — spawn a real `conc.spawn` actor, drive
#     it through Register → Store → Lookup sequences via the
#     `try_reserve` / `store_response` / `lookup` / `forget` /
#     `purge` wrappers. `[concurrent]`.
#
#   * **`dispatch_with_cache`** — wires a real `route.Registry` to
#     the cache, makes two requests with the same key, asserts the
#     handler ran exactly once. `[concurrent, time]`.
#
# Concurrent-dup coalescing under timeout is exercised by stuffing
# a fake `InFlight` slot into the actor before calling
# `dispatch_with_cache` with a short `max_wait_ms`; the wrapper
# falls back to running the handler on timeout. The genuine
# multi-thread race (two handlers concurrently calling
# `dispatch_with_cache` from separate threads) needs OS-thread
# scheduling that lex 0.9.3 doesn't expose; documented as deferred
# to the conformance harness in #10.

import "std.conc" as conc

import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.time" as time

import "std.tuple" as tuple

import "lex-schema/json_value" as jv

import "../src/envelope" as env

import "../src/headers" as h

import "../src/idempotency" as idem

import "../src/party" as party

import "../src/route" as route

# ---- Test plumbing ----------------------------------------------
fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b {
    pass()
  } else {
    fail(label)
  }
}

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got {
    pass()
  } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, want)
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, got))
  }
}

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got {
    pass()
  } else {
    let m1 := str.concat(label, ": want=")
    let m2 := str.concat(m1, int.to_str(want))
    let m3 := str.concat(m2, " got=")
    fail(str.concat(m3, int.to_str(got)))
  }
}

fn and_ok(a :: Result[Unit, Str], b :: Result[Unit, Str]) -> Result[Unit, Str] {
  match a {
    Err(_) => a,
    Ok(_) => b,
  }
}

# ---- Fixtures ---------------------------------------------------
fn mk_headers(rid :: Str, cc :: Str, pid :: Str) -> h.OcpiHeaders {
  h.new("Token x", rid, "corr-1", party.new(cc, pid), party.new("DE", "ABC"))
}

fn mk_request(method :: Str, path :: Str, rid :: Str) -> route.OcpiRequest {
  route.request(method, "cdrs", path, map.new(), map.new(), mk_headers(rid, "NL", "EXM"), JNull)
}

fn mk_response(code :: Int, message :: Str) -> env.OcpiResponse {
  { status_code: code, status_message: message, data: JNull, timestamp: "2026-05-16T00:00:00Z" }
}

# ---- key_from_request / key_str --------------------------------
fn test_key_from_request_happy() -> Result[Unit, Str] {
  let req := mk_request("POST", "/ocpi/2.2.1/cdrs", "req-123")
  match idem.key_from_request(req) {
    None => fail("expected Some(key)"),
    Some(k) => {
      assert_eq_str("POST|/ocpi/2.2.1/cdrs|req-123|NL|EXM", idem.key_str(k), "key serialisation")
    },
  }
}

fn test_key_from_request_missing_id() -> Result[Unit, Str] {
  let req := mk_request("POST", "/cdrs", "")
  match idem.key_from_request(req) {
    None => pass(),
    Some(_) => fail("expected None when request_id empty"),
  }
}

# ---- Pure handler — basic flow ---------------------------------
fn empty(cap :: Int) -> idem.CacheState {
  idem.empty_state(cap)
}

fn snd_after(state :: idem.CacheState, msg :: idem.CacheMsg) -> idem.CacheReply {
  tuple.snd(idem.cache_handler(state, msg))
}

fn fst_after(state :: idem.CacheState, msg :: idem.CacheMsg) -> idem.CacheState {
  tuple.fst(idem.cache_handler(state, msg))
}

fn test_handler_reserve_then_hit() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k1"))
  let s2 := fst_after(s1, Store("k1", mk_response(1000, "OK"), 999999999999))
  match snd_after(s2, TryReserve("k1")) {
    Hit(h) => assert_eq_int(1000, h.response.status_code, "cached status_code"),
    _ => fail("expected Hit after Store"),
  }
}

fn test_handler_reserve_inflight_wait() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k2"))
  match snd_after(s1, TryReserve("k2")) {
    Wait => pass(),
    _ => fail("expected Wait while InFlight"),
  }
}

fn test_handler_first_reserve_run() -> Result[Unit, Str] {
  match snd_after(empty(10), TryReserve("k3")) {
    Run => pass(),
    _ => fail("expected Run on first reserve"),
  }
}

fn test_handler_lookup_miss() -> Result[Unit, Str] {
  match snd_after(empty(10), Lookup("k-nope", 0)) {
    Miss => pass(),
    _ => fail("expected Miss for never-registered key"),
  }
}

fn test_handler_lookup_inflight_yields_wait() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k4"))
  match snd_after(s1, Lookup("k4", 0)) {
    Wait => pass(),
    _ => fail("expected Wait on InFlight lookup"),
  }
}

fn test_handler_lookup_completed_hit() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k5"))
  let s2 := fst_after(s1, Store("k5", mk_response(1000, "OK"), 999999999999))
  match snd_after(s2, Lookup("k5", 100)) {
    Hit(h) => assert_eq_int(1000, h.response.status_code, "lookup hit"),
    _ => fail("expected Hit for completed lookup"),
  }
}

fn test_handler_lookup_expired_miss() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k6"))
  let s2 := fst_after(s1, Store("k6", mk_response(1000, "OK"), 50))
  match snd_after(s2, Lookup("k6", 100)) {
    Miss => pass(),
    _ => fail("expected Miss for expired entry"),
  }
}

fn test_handler_forget_clears_inflight() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k7"))
  let s2 := fst_after(s1, Forget("k7"))
  match snd_after(s2, TryReserve("k7")) {
    Run => pass(),
    _ => fail("expected Run after Forget cleared InFlight"),
  }
}

# ---- Purge ------------------------------------------------------
fn test_handler_purge_drops_expired() -> Result[Unit, Str] {
  let s1 := fst_after(empty(10), TryReserve("k8"))
  let s2 := fst_after(s1, Store("k8", mk_response(1000, "OK"), 50))
  let s3 := fst_after(s2, TryReserve("k9"))
  let s4 := fst_after(s3, Store("k9", mk_response(1000, "OK"), 200))
  let s5 := fst_after(s4, Purge(100))
  let k8_gone := match snd_after(s5, Lookup("k8", 100)) {
    Miss => pass(),
    _ => fail("k8 should be purged"),
  }
  let k9_kept := match snd_after(s5, Lookup("k9", 100)) {
    Hit(_) => pass(),
    _ => fail("k9 should survive purge"),
  }
  and_ok(k8_gone, k9_kept)
}

# ---- LRU eviction ----------------------------------------------
fn test_lru_evicts_oldest() -> Result[Unit, Str] {
  let cap := 3
  let s1 := fst_after(empty(cap), Store("a", mk_response(1000, "OK"), 999999999999))
  let s2 := fst_after(s1, Store("b", mk_response(1000, "OK"), 999999999999))
  let s3 := fst_after(s2, Store("c", mk_response(1000, "OK"), 999999999999))
  let s4 := fst_after(s3, Store("d", mk_response(1000, "OK"), 999999999999))
  let a_gone := match snd_after(s4, Lookup("a", 0)) {
    Miss => pass(),
    _ => fail("oldest entry a should be evicted"),
  }
  let bcd_kept := match snd_after(s4, Lookup("d", 0)) {
    Hit(_) => pass(),
    _ => fail("d should be present"),
  }
  and_ok(a_gone, bcd_kept)
}

fn test_lru_touch_promotes() -> Result[Unit, Str] {
  let cap := 3
  let s1 := fst_after(empty(cap), Store("a", mk_response(1000, "OK"), 999999999999))
  let s2 := fst_after(s1, Store("b", mk_response(1000, "OK"), 999999999999))
  let s3 := fst_after(s2, Store("c", mk_response(1000, "OK"), 999999999999))
  let s4 := fst_after(s3, TryReserve("a"))
  let s5 := fst_after(s4, Store("d", mk_response(1000, "OK"), 999999999999))
  let a_kept := match snd_after(s5, Lookup("a", 0)) {
    Hit(_) => pass(),
    _ => fail("a should survive (touched recently)"),
  }
  let b_gone := match snd_after(s5, Lookup("b", 0)) {
    Miss => pass(),
    _ => fail("b should be evicted (now oldest)"),
  }
  and_ok(a_kept, b_gone)
}

fn test_lru_capacity_zero_unbounded() -> Result[Unit, Str] {
  let s := list.fold(["a", "b", "c", "d", "e"], empty(0), fn (acc :: idem.CacheState, k :: Str) -> idem.CacheState {
    fst_after(acc, Store(k, mk_response(1000, "OK"), 999999999999))
  })
  match snd_after(s, Lookup("a", 0)) {
    Hit(_) => pass(),
    _ => fail("capacity=0 should be unbounded"),
  }
}

# ---- Actor end-to-end (concurrent) ----------------------------
fn test_actor_basic_flow() -> [concurrent] Result[Unit, Str] {
  let actor := idem.new_cache(10)
  let r1_ok := match idem.try_reserve(actor, "ak1") {
    Run => pass(),
    _ => fail("first call should Run"),
  }
  let __lex_discard_1 := idem.store_response(actor, "ak1", mk_response(1000, "OK"), 999999999999)
  let r2_ok := match idem.try_reserve(actor, "ak1") {
    Hit(h) => assert_eq_int(1000, h.response.status_code, "actor hit"),
    _ => fail("second call should Hit"),
  }
  and_ok(r1_ok, r2_ok)
}

fn test_actor_forget_releases() -> [concurrent] Result[Unit, Str] {
  let actor := idem.new_cache(10)
  let __lex_discard_2 := idem.try_reserve(actor, "ak2")
  let __lex_discard_3 := idem.forget(actor, "ak2")
  match idem.try_reserve(actor, "ak2") {
    Run => pass(),
    _ => fail("Forget should release InFlight"),
  }
}

fn test_actor_lookup_pending() -> [concurrent] Result[Unit, Str] {
  let actor := idem.new_cache(10)
  let __lex_discard_4 := idem.try_reserve(actor, "ak3")
  match idem.lookup(actor, "ak3", 0) {
    Wait => pass(),
    _ => fail("lookup should Wait after reserve"),
  }
}

# ---- dispatch_with_cache (concurrent, time) -------------------
#
# `route.Handler` is typed pure (no effects), so we can't increment
# a counter actor from inside a handler closure. Instead, each test
# uses two **distinct named** handlers that return different
# payloads. If the cache works, the second `dispatch_with_cache`
# call still returns the first handler's response (cache hit). If
# the cache is missing, it returns the second handler's response.
#
# Why named handlers, not a `handler_returning(code)` closure
# factory: closures-over-parameters don't capture cleanly in
# 0.9.3 — invoking the factory twice returns a closure whose
# captured `code` matches the FIRST invocation. (See
# `debug_two_dispatches_no_cache` below: building two registries
# from a factory yields two handlers that both return the first
# value.) Hardcoded function bodies avoid the gotcha.
fn handler_1000(_req :: route.OcpiRequest) -> route.HandlerResult {
  HOk(JStr("1000"))
}

fn handler_2000(_req :: route.OcpiRequest) -> route.HandlerResult {
  HOk(JStr("2000"))
}

fn registry_1000() -> route.Registry {
  route.handler(route.new(), "POST", "cdrs", handler_1000)
}

fn registry_2000() -> route.Registry {
  route.handler(route.new(), "POST", "cdrs", handler_2000)
}

fn data_as_str(r :: env.OcpiResponse) -> Str {
  match r.data {
    JStr(s) => s,
    _ => "<not-str>",
  }
}

fn test_dispatch_dedups_same_key() -> [concurrent, time] Result[Unit, Str] {
  let cache := idem.new_cache(100)
  let cfg := idem.default_config()
  let req := mk_request("POST", "/cdrs", "dedup-1")
  let __lex_discard_5 := idem.dispatch_with_cache(registry_1000(), cache, cfg, req, "t")
  let r2 := idem.dispatch_with_cache(registry_2000(), cache, cfg, req, "t")
  assert_eq_str("1000", data_as_str(r2), "cache should serve first payload")
}

fn test_dispatch_distinct_keys_both_run() -> [concurrent, time] Result[Unit, Str] {
  let cache := idem.new_cache(100)
  let cfg := idem.default_config()
  let r1 := idem.dispatch_with_cache(registry_1000(), cache, cfg, mk_request("POST", "/cdrs", "x-1"), "t")
  let r2 := idem.dispatch_with_cache(registry_2000(), cache, cfg, mk_request("POST", "/cdrs", "x-2"), "t")
  let a := assert_eq_str("1000", data_as_str(r1), "first call payload")
  let b := assert_eq_str("2000", data_as_str(r2), "second call payload")
  and_ok(a, b)
}

fn test_dispatch_no_request_id_skips_cache() -> [concurrent, time] Result[Unit, Str] {
  let cache := idem.new_cache(100)
  let cfg := idem.default_config()
  let req := mk_request("POST", "/cdrs", "")
  let r1 := idem.dispatch_with_cache(registry_1000(), cache, cfg, req, "t")
  let r2 := idem.dispatch_with_cache(registry_2000(), cache, cfg, req, "t")
  let a := assert_eq_str("1000", data_as_str(r1), "no-rid first")
  let b := assert_eq_str("2000", data_as_str(r2), "no-rid second")
  and_ok(a, b)
}

# Force the in-flight fallback path: pre-set an InFlight slot in the
# cache and dispatch with a tiny `max_wait_ms`. The wrapper should
# poll, time out, clear the marker, and run the handler.
fn test_dispatch_inflight_fallback_after_timeout() -> [concurrent, time] Result[Unit, Str] {
  let cache := idem.new_cache(100)
  let cfg := { ttl_ms: 24 * 60 * 60 * 1000, poll_interval_ms: 5, max_wait_ms: 20 }
  let req := mk_request("POST", "/cdrs", "stuck-1")
  let key := idem.key_str({ method: "POST", path: "/cdrs", request_id: "stuck-1", from_cc: "NL", from_party_id: "EXM" })
  let __lex_discard_6 := idem.try_reserve(cache, key)
  let r := idem.dispatch_with_cache(registry_1000(), cache, cfg, req, "t")
  assert_eq_str("1000", data_as_str(r), "timeout fallback should run handler")
}

# ---- Suite + runner -------------------------------------------
fn pure_suite() -> List[Result[Unit, Str]] {
  [test_key_from_request_happy(), test_key_from_request_missing_id(), test_handler_first_reserve_run(), test_handler_reserve_then_hit(), test_handler_reserve_inflight_wait(), test_handler_lookup_miss(), test_handler_lookup_inflight_yields_wait(), test_handler_lookup_completed_hit(), test_handler_lookup_expired_miss(), test_handler_forget_clears_inflight(), test_handler_purge_drops_expired(), test_lru_evicts_oldest(), test_lru_touch_promotes(), test_lru_capacity_zero_unbounded()]
}

fn actor_suite() -> [concurrent] List[Result[Unit, Str]] {
  [test_actor_basic_flow(), test_actor_forget_releases(), test_actor_lookup_pending()]
}

fn dispatch_suite() -> [concurrent, time] List[Result[Unit, Str]] {
  [test_dispatch_dedups_same_key(), test_dispatch_distinct_keys_both_run(), test_dispatch_no_request_id_skips_cache(), test_dispatch_inflight_fallback_after_timeout()]
}

fn count_failures(rs :: List[Result[Unit, Str]]) -> Int {
  list.fold(rs, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

fn run_all() -> [concurrent, time] Int {
  count_failures(pure_suite()) + count_failures(actor_suite()) + count_failures(dispatch_suite())
}

