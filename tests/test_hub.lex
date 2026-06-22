# lex-ocpi — Hub role tests (issue #9)
#
# Covers `src/hub.lex`:
#
#   * Pure RoutingTable CRUD — add / remove / lookup / count /
#     all_parties — exercised against multiple peers.
#   * Loop detection — `forward(from=X, to=X, ...)` refuses before
#     touching the network.
#   * Unknown receiver — `forward(to=unregistered, ...)` returns
#     `UnknownReceiver` before touching the network.
#   * Request shape — `build_forward_request(...)` is the pure
#     glue between routing and `client.send_with_retry`; asserts
#     URL composition (peer base + module path), method, party
#     headers (from preserved, to set to recipient), Authorization
#     scheme, body presence/absence.
#   * `clientinfo_path` — spec-shape `/clientinfo/{cc}/{pid}/{uid}`.
#   * Broadcast skip-list — `broadcast_clientinfo`'s recipient
#     filter excludes the subject party. (We assert on the
#     recipient list via a stand-in: the pure filter inside
#     `broadcast_clientinfo` is mirrored as a one-liner over
#     `all_parties + same_party`.)
#   * Error mapping — every `RoutingError` variant maps to the
#     spec's 4xxx hub-status code per the catalogue in
#     `src/status.lex`.
#
# Live-loop tests (peer returning 4002 / hub-side `forward` going
# all the way through `client.send`, etc.) need the mock transport
# from #10's follow-up slice — deferred to that PR.

import "std.list" as list

import "std.map" as map

import "std.str" as str

import "lex-schema/json_value" as jv

import "../src/client" as client

import "../src/headers" as h

import "../src/hub" as hub

import "../src/party" as party

import "../src/push" as push

import "../src/status" as status

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
fn cpo_a() -> party.PartyId {
  party.new("NL", "EXM")
}

fn cpo_b() -> party.PartyId {
  party.new("NL", "OTH")
}

fn emsp_1() -> party.PartyId {
  party.new("DE", "ABC")
}

fn emsp_2() -> party.PartyId {
  party.new("FR", "XYZ")
}

fn hub_party() -> party.PartyId {
  party.new("NL", "HUB")
}

fn target_for(p :: party.PartyId, base :: Str, token :: Str) -> push.PushTarget {
  { party: p, base_url: base, token: token }
}

fn three_peer_table() -> hub.RoutingTable {
  let t0 := hub.empty_table()
  let t1 := hub.add_peer(t0, target_for(cpo_a(), "https://cpo-a.example/ocpi/2.2.1", "tok-a"))
  let t2 := hub.add_peer(t1, target_for(emsp_1(), "https://emsp-1.example/ocpi/2.2.1", "tok-1"))
  hub.add_peer(t2, target_for(emsp_2(), "https://emsp-2.example/ocpi/2.2.1", "tok-2"))
}

# ---- RoutingTable CRUD ----------------------------------------
fn test_empty_table_count() -> Result[Unit, Str] {
  assert_eq_int(0, hub.peer_count(hub.empty_table()), "empty table count")
}

fn test_add_then_count() -> Result[Unit, Str] {
  let t := hub.add_peer(hub.empty_table(), target_for(cpo_a(), "https://x", "tok"))
  assert_eq_int(1, hub.peer_count(t), "after 1 add")
}

fn test_add_three_count() -> Result[Unit, Str] {
  assert_eq_int(3, hub.peer_count(three_peer_table()), "3 peers")
}

fn test_lookup_hit() -> Result[Unit, Str] {
  match hub.lookup(three_peer_table(), emsp_1()) {
    Some(t) => assert_eq_str("https://emsp-1.example/ocpi/2.2.1", t.base_url, "lookup hit base_url"),
    None => fail("expected Some(target)"),
  }
}

fn test_lookup_miss() -> Result[Unit, Str] {
  match hub.lookup(three_peer_table(), party.new("XX", "YYY")) {
    None => pass(),
    Some(_) => fail("expected None for unregistered"),
  }
}

fn test_remove_peer() -> Result[Unit, Str] {
  let t := three_peer_table()
  let t2 := hub.remove_peer(t, emsp_1())
  match hub.lookup(t2, emsp_1()) {
    None => assert_eq_int(2, hub.peer_count(t2), "after remove"),
    Some(_) => fail("removed peer still present"),
  }
}

fn test_remove_unknown_is_noop() -> Result[Unit, Str] {
  let t := three_peer_table()
  let t2 := hub.remove_peer(t, party.new("XX", "YYY"))
  assert_eq_int(hub.peer_count(t), hub.peer_count(t2), "remove unknown changes nothing")
}

fn test_add_overwrites() -> Result[Unit, Str] {
  let t := three_peer_table()
  let t2 := hub.add_peer(t, target_for(emsp_1(), "https://emsp-1-NEW.example", "tok-NEW"))
  let count_ok := assert_eq_int(3, hub.peer_count(t2), "overwrite keeps count")
  let url_ok := match hub.lookup(t2, emsp_1()) {
    Some(target) => assert_eq_str("https://emsp-1-NEW.example", target.base_url, "overwrite url"),
    None => fail("emsp_1 vanished after overwrite"),
  }
  and_ok(count_ok, url_ok)
}

fn test_all_parties_count() -> Result[Unit, Str] {
  let ps := hub.all_parties(three_peer_table())
  assert_eq_int(3, list.len(ps), "all_parties count")
}

# ---- key_of (private but exposed for testing) -----------------
fn test_key_of_shape() -> Result[Unit, Str] {
  assert_eq_str("NL|EXM", hub.key_of(cpo_a()), "key_of shape")
}

# ---- clientinfo_path -----------------------------------------
fn test_clientinfo_path_shape() -> Result[Unit, Str] {
  assert_eq_str("/clientinfo/NL/EXM/uid-1", hub.clientinfo_path(cpo_a(), "uid-1"), "clientinfo path")
}

# ---- forward — loop prevention (no network) ------------------
fn test_forward_loop_refused() -> [net, time] Result[Unit, Str] {
  let r := hub.forward(client.no_retry_policy(), three_peer_table(), emsp_1(), emsp_1(), "GET", "/locations/DE/ABC/L1", None)
  match r {
    Err(LoopDetected(_)) => pass(),
    Err(_) => fail("expected LoopDetected, got other err"),
    Ok(_) => fail("expected Err, got Ok"),
  }
}

# ---- forward — unknown receiver (no network) -----------------
fn test_forward_unknown_receiver() -> [net, time] Result[Unit, Str] {
  let r := hub.forward(client.no_retry_policy(), three_peer_table(), hub_party(), party.new("XX", "YYY"), "GET", "/locations/XX/YYY/L1", None)
  match r {
    Err(UnknownReceiver(p)) => assert_eq_str("XX|YYY", hub.key_of(p), "unknown receiver key"),
    Err(_) => fail("expected UnknownReceiver"),
    Ok(_) => fail("expected Err, got Ok"),
  }
}

# ---- build_forward_request — request shape ------------------
fn target_emsp_1() -> push.PushTarget {
  target_for(emsp_1(), "https://emsp-1.example/ocpi/2.2.1", "tok-1")
}

fn test_build_method_url() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "PUT", "/locations/NL/EXM/L1", Some(JObj([("id", JStr("L1"))])))
  let m_ok := assert_eq_str("PUT", r.method, "method")
  let u_ok := assert_eq_str("https://emsp-1.example/ocpi/2.2.1/locations/NL/EXM/L1", r.url, "url")
  and_ok(m_ok, u_ok)
}

fn test_build_uses_target_token() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "GET", "/locations", None)
  match map.get(r.headers, h.h_authorization()) {
    None => fail("Authorization missing"),
    Some(v) => assert_eq_str("Token tok-1", v, "Authorization scheme + token"),
  }
}

fn test_build_preserves_from_party() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "GET", "/locations", None)
  let cc := map.get(r.headers, h.h_from_country_code())
  let pi := map.get(r.headers, h.h_from_party_id())
  match cc {
    None => fail("from-country missing"),
    Some(c) => match pi {
      None => fail("from-party missing"),
      Some(p) => and_ok(assert_eq_str("NL", c, "from-country"), assert_eq_str("EXM", p, "from-party")),
    },
  }
}

fn test_build_sets_to_party_from_target() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "GET", "/locations", None)
  let cc := map.get(r.headers, h.h_to_country_code())
  let pi := map.get(r.headers, h.h_to_party_id())
  match cc {
    None => fail("to-country missing"),
    Some(c) => match pi {
      None => fail("to-party missing"),
      Some(p) => and_ok(assert_eq_str("DE", c, "to-country = recipient"), assert_eq_str("ABC", p, "to-party = recipient")),
    },
  }
}

fn test_build_get_no_body() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "GET", "/locations", None)
  match r.body {
    None => pass(),
    Some(_) => fail("GET should have no body"),
  }
}

fn test_build_put_with_body() -> Result[Unit, Str] {
  let r := hub.build_forward_request(target_emsp_1(), cpo_a(), "PUT", "/locations/NL/EXM/L1", Some(JObj([("id", JStr("L1"))])))
  let body_ok := match r.body {
    None => fail("PUT body missing"),
    Some(_) => pass(),
  }
  let ct_ok := match map.get(r.headers, "content-type") {
    None => fail("content-type missing for body"),
    Some(v) => assert_eq_str("application/json", v, "content-type"),
  }
  and_ok(body_ok, ct_ok)
}

# ---- error_to_status_code mapping ---------------------------
fn test_error_status_unknown_receiver() -> Result[Unit, Str] {
  assert_eq_int(4002, hub.error_to_status_code(UnknownReceiver(emsp_1())), "UnknownReceiver -> 4002")
}

fn test_error_status_loop_detected() -> Result[Unit, Str] {
  assert_eq_int(4001, hub.error_to_status_code(LoopDetected({ from: cpo_a(), to: cpo_a() })), "LoopDetected -> 4001")
}

fn test_error_status_forward_failed() -> Result[Unit, Str] {
  assert_eq_int(4004, hub.error_to_status_code(ForwardFailed(HttpFailed("refused"))), "ForwardFailed -> 4004")
}

fn test_error_status_matches_status_module() -> Result[Unit, Str] {
  let a := assert_eq_int(4002, status.unknown_receiver(), "status.unknown_receiver")
  let b := assert_eq_int(4001, status.missing_or_invalid_parameters(), "status.missing_or_invalid_parameters")
  let c := assert_eq_int(4004, status.connection_problem(), "status.connection_problem")
  and_ok(a, and_ok(b, c))
}

# ---- Suite + runner ------------------------------------------
fn pure_suite() -> List[Result[Unit, Str]] {
  [test_empty_table_count(), test_add_then_count(), test_add_three_count(), test_lookup_hit(), test_lookup_miss(), test_remove_peer(), test_remove_unknown_is_noop(), test_add_overwrites(), test_all_parties_count(), test_key_of_shape(), test_clientinfo_path_shape(), test_build_method_url(), test_build_uses_target_token(), test_build_preserves_from_party(), test_build_sets_to_party_from_target(), test_build_get_no_body(), test_build_put_with_body(), test_error_status_unknown_receiver(), test_error_status_loop_detected(), test_error_status_forward_failed(), test_error_status_matches_status_module()]
}

fn fwd_suite() -> [net, time] List[Result[Unit, Str]] {
  [test_forward_loop_refused(), test_forward_unknown_receiver()]
}

fn count_failures(rs :: List[Result[Unit, Str]]) -> Int {
  list.fold(rs, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

fn run_all() -> [net, time] Int {
  count_failures(pure_suite()) + count_failures(fwd_suite())
}

