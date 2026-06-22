# lex-ocpi — Commands async runtime tests
#
# Covers `src/commands_async.lex`:
#
#   - inflight_handler — the pure transition function across all 4
#     message kinds + the membership / completion split. This is
#     where the registry's invariant lives; testing it pure means we
#     don't need [concurrent] for these cases.
#
#   - Actor end-to-end — spawn an inflight, drive it through a
#     real Register → Complete → Lookup sequence with `conc.ask` /
#     `conc.tell`, and verify the state machine matches the pure
#     handler. Effect: [concurrent].
#
#   - compute_deadline_from — pure deadline math (ms → ns).
#
#   - wait_for_result — three flows:
#       * happy path — register, complete, then wait → Ok(result)
#         (completion has already happened so no real polling)
#       * unknown id — never registered → Err(WaitUnknown)
#       * timeout — registered, never completed, short deadline →
#         Err(WaitTimeout) after ~10ms.
#     Effects: [concurrent, time].
#
#   - parse_result_post — pure parser across the three outcomes
#     (PostCompleted / PostBadResponseId / PostBadBody) +
#     result_post_handler_result mapping.
#
# `callback_result` requires `[net]` and a live HTTP target; like
# the slice 1 sender, it's covered by a future end-to-end live-port
# round-trip (issue #4 keeps the doc anchor; this PR closes it).

import "std.conc" as conc

import "std.list" as list

import "std.map" as map

import "std.str" as str

import "std.tuple" as tuple

import "lex-schema/json_value" as jv

import "../src/commands" as cmds

import "../src/commands_async" as ca

import "../src/headers" as h

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

# ---- inflight_handler (pure) -----------------------------------
fn empty_state() -> Map[Str, Option[cmds.CommandResult]] {
  map.new()
}

fn test_handler_register() -> Result[Unit, Str] {
  let step := ca.inflight_handler(empty_state(), Register("R1"))
  let state2 := tuple.fst(step)
  match tuple.snd(step) {
    AckRegistered => assert_true(map.has(state2, "R1"), "R1 not registered"),
    _ => fail("expected AckRegistered"),
  }
}

fn test_handler_lookup_unknown() -> Result[Unit, Str] {
  let step := ca.inflight_handler(empty_state(), Lookup("R-none"))
  match tuple.snd(step) {
    LookupUnknown => pass(),
    _ => fail("expected LookupUnknown for never-registered id"),
  }
}

fn test_handler_lookup_pending() -> Result[Unit, Str] {
  let s1 := tuple.fst(ca.inflight_handler(empty_state(), Register("R2")))
  let step := ca.inflight_handler(s1, Lookup("R2"))
  match tuple.snd(step) {
    LookupPending => pass(),
    _ => fail("expected LookupPending after Register"),
  }
}

fn test_handler_complete_then_lookup() -> Result[Unit, Str] {
  let s1 := tuple.fst(ca.inflight_handler(empty_state(), Register("R3")))
  let s2 := tuple.fst(ca.inflight_handler(s1, Complete("R3", cmds.result_accepted())))
  match tuple.snd(ca.inflight_handler(s2, Lookup("R3"))) {
    LookupReady(r) => match r.result {
      ResAccepted => pass(),
      _ => fail("expected ResAccepted in LookupReady"),
    },
    _ => fail("expected LookupReady after Complete"),
  }
}

# Complete-without-Register: the spec doesn't require pre-registration
# in the wire protocol, so the handler accepts it. Future Lookup will
# see Ready, not Pending — matches the natural reading of the map.
fn test_handler_complete_without_register() -> Result[Unit, Str] {
  let s1 := tuple.fst(ca.inflight_handler(empty_state(), Complete("R-orphan", cmds.result_timeout())))
  match tuple.snd(ca.inflight_handler(s1, Lookup("R-orphan"))) {
    LookupReady(r) => match r.result {
      ResTimeout => pass(),
      _ => fail("expected ResTimeout"),
    },
    _ => fail("expected LookupReady"),
  }
}

fn test_handler_forget() -> Result[Unit, Str] {
  let s1 := tuple.fst(ca.inflight_handler(empty_state(), Register("R4")))
  let s2 := tuple.fst(ca.inflight_handler(s1, Complete("R4", cmds.result_accepted())))
  let step := ca.inflight_handler(s2, Forget("R4"))
  match tuple.snd(step) {
    AckForgotten => assert_true(map.has(tuple.fst(step), "R4") == false, "R4 still present after Forget"),
    _ => fail("expected AckForgotten"),
  }
}

# ---- Actor end-to-end (concurrent) -----------------------------
fn test_actor_register_then_complete() -> [concurrent] Result[Unit, Str] {
  let actor := ca.new_inflight()
  let __lex_discard_1 := ca.register(actor, "A-1")
  let __lex_discard_2 := ca.complete(actor, "A-1", cmds.result_accepted())
  match ca.lookup(actor, "A-1") {
    LookupReady(r) => match r.result {
      ResAccepted => pass(),
      _ => fail("expected ResAccepted via actor"),
    },
    _ => fail("expected LookupReady from actor"),
  }
}

fn test_actor_unknown_id() -> [concurrent] Result[Unit, Str] {
  let actor := ca.new_inflight()
  match ca.lookup(actor, "A-never") {
    LookupUnknown => pass(),
    _ => fail("expected LookupUnknown for fresh actor"),
  }
}

fn test_actor_pending() -> [concurrent] Result[Unit, Str] {
  let actor := ca.new_inflight()
  let __lex_discard_3 := ca.register(actor, "A-2")
  match ca.lookup(actor, "A-2") {
    LookupPending => pass(),
    _ => fail("expected LookupPending after register"),
  }
}

fn test_actor_forget() -> [concurrent] Result[Unit, Str] {
  let actor := ca.new_inflight()
  let __lex_discard_4 := ca.register(actor, "A-3")
  let __lex_discard_5 := ca.complete(actor, "A-3", cmds.result_failed())
  let __lex_discard_6 := ca.forget(actor, "A-3")
  match ca.lookup(actor, "A-3") {
    LookupUnknown => pass(),
    _ => fail("expected LookupUnknown after forget"),
  }
}

# ---- compute_deadline_from (pure) ------------------------------
fn test_compute_deadline_zero() -> Result[Unit, Str] {
  assert_true(ca.compute_deadline_from(0, 0) == 0, "0+0 -> 0")
}

fn test_compute_deadline_positive() -> Result[Unit, Str] {
  assert_true(ca.compute_deadline_from(0, 1500) == 1500000000, "1500ms -> 1.5e9 ns")
}

fn test_compute_deadline_offset_from_start() -> Result[Unit, Str] {
  let start := 5000000000
  assert_true(ca.compute_deadline_from(start, 250) == 5250000000, "start + 250ms")
}

# ---- wait_for_result (concurrent, time) ------------------------
# Happy path — the result has already been completed before the
# wait starts, so the very first poll hits LookupReady and the loop
# returns immediately. No sleeping under test.
fn test_wait_returns_completed() -> [concurrent, time] Result[Unit, Str] {
  let actor := ca.new_inflight()
  let __lex_discard_7 := ca.register(actor, "W-1")
  let __lex_discard_8 := ca.complete(actor, "W-1", cmds.result_accepted())
  match ca.wait_for_result(actor, "W-1", 1000, 10) {
    Ok(r) => match r.result {
      ResAccepted => pass(),
      _ => fail("expected ResAccepted from wait"),
    },
    Err(_) => fail("expected Ok from already-completed wait"),
  }
}

fn test_wait_unknown_id() -> [concurrent, time] Result[Unit, Str] {
  let actor := ca.new_inflight()
  match ca.wait_for_result(actor, "W-never", 1000, 10) {
    Err(WaitUnknown) => pass(),
    Err(WaitTimeout) => fail("expected WaitUnknown not WaitTimeout"),
    Ok(_) => fail("expected Err for unknown id"),
  }
}

# Timeout — register, never complete, short deadline.
# 10ms timeout, 5ms poll interval → wakes at most three times.
fn test_wait_timeout() -> [concurrent, time] Result[Unit, Str] {
  let actor := ca.new_inflight()
  let __lex_discard_9 := ca.register(actor, "W-2")
  match ca.wait_for_result(actor, "W-2", 10, 5) {
    Err(WaitTimeout) => pass(),
    Err(WaitUnknown) => fail("expected WaitTimeout not WaitUnknown"),
    Ok(_) => fail("expected Err(WaitTimeout)"),
  }
}

# ---- parse_result_post (pure) ----------------------------------
fn empty_headers() -> h.OcpiHeaders {
  h.new("", "", "", party.new("", ""), party.new("", ""))
}

fn mk_request(path :: Str, body :: jv.Json) -> route.OcpiRequest {
  route.request(route.post(), "commands.result", path, map.new(), map.new(), empty_headers(), body)
}

# Last path segment as the response_id. This is one reasonable
# scheme; the parser lets callers pick anything via the extractor fn.
fn last_path_segment(req :: route.OcpiRequest) -> Option[Str] {
  list.head(list.reverse(str.split(req.path, "/")))
}

fn test_parse_completed() -> Result[Unit, Str] {
  let body := JObj([("result", JStr("ACCEPTED"))])
  let req := mk_request("/ocpi/emsp/cb/abc123", body)
  match ca.parse_result_post(req, last_path_segment) {
    PostCompleted(p) => match p.result.result {
      ResAccepted => assert_eq_str("abc123", p.response_id, "response_id"),
      _ => fail("expected ResAccepted"),
    },
    PostBadResponseId(m) => fail(str.concat("unexpected bad id: ", m)),
    PostBadBody(m) => fail(str.concat("unexpected bad body: ", m)),
  }
}

fn test_parse_bad_response_id() -> Result[Unit, Str] {
  let body := JObj([("result", JStr("ACCEPTED"))])
  let extractor := fn (__lex_discard_10 :: route.OcpiRequest) -> Option[Str] {
    None
  }
  match ca.parse_result_post(mk_request("/anything", body), extractor) {
    PostBadResponseId(_) => pass(),
    _ => fail("expected PostBadResponseId"),
  }
}

fn test_parse_bad_body_missing_result() -> Result[Unit, Str] {
  let body := JObj([])
  let req := mk_request("/ocpi/emsp/cb/abc", body)
  match ca.parse_result_post(req, last_path_segment) {
    PostBadBody(_) => pass(),
    _ => fail("expected PostBadBody for missing result"),
  }
}

fn test_parse_bad_body_unknown_result() -> Result[Unit, Str] {
  let body := JObj([("result", JStr("MAYBE_LATER"))])
  let req := mk_request("/ocpi/emsp/cb/abc", body)
  match ca.parse_result_post(req, last_path_segment) {
    PostBadBody(_) => pass(),
    _ => fail("expected PostBadBody for unknown result"),
  }
}

# ---- result_post_handler_result (pure) -------------------------
fn test_handler_result_ok() -> Result[Unit, Str] {
  let p := PostCompleted({ response_id: "abc", result: cmds.result_accepted() })
  match ca.result_post_handler_result(p) {
    HOkEmpty => pass(),
    _ => fail("expected HOkEmpty for completed"),
  }
}

fn test_handler_result_bad_id() -> Result[Unit, Str] {
  match ca.result_post_handler_result(PostBadResponseId("nope")) {
    HErr(err) => assert_true(err.code == 2001, "expected 2001"),
    _ => fail("expected HErr"),
  }
}

fn test_handler_result_bad_body() -> Result[Unit, Str] {
  match ca.result_post_handler_result(PostBadBody("nope")) {
    HErr(err) => assert_true(err.code == 2001, "expected 2001"),
    _ => fail("expected HErr"),
  }
}

# ---- Suite + runner --------------------------------------------
fn pure_suite() -> List[Result[Unit, Str]] {
  [test_handler_register(), test_handler_lookup_unknown(), test_handler_lookup_pending(), test_handler_complete_then_lookup(), test_handler_complete_without_register(), test_handler_forget(), test_compute_deadline_zero(), test_compute_deadline_positive(), test_compute_deadline_offset_from_start(), test_parse_completed(), test_parse_bad_response_id(), test_parse_bad_body_missing_result(), test_parse_bad_body_unknown_result(), test_handler_result_ok(), test_handler_result_bad_id(), test_handler_result_bad_body()]
}

fn actor_suite() -> [concurrent] List[Result[Unit, Str]] {
  [test_actor_register_then_complete(), test_actor_unknown_id(), test_actor_pending(), test_actor_forget()]
}

fn wait_suite() -> [concurrent, time] List[Result[Unit, Str]] {
  [test_wait_returns_completed(), test_wait_unknown_id(), test_wait_timeout()]
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
  count_failures(pure_suite()) + count_failures(actor_suite()) + count_failures(wait_suite())
}

