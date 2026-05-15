# lex-ocpi — headers parsing/building tests

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "../src/headers" as headers
import "../src/party"   as party

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else {
    fail(str.concat(label, str.concat(": want=", str.concat(want,
      str.concat(" got=", got)))))
  }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- from_map ---------------------------------------------------

fn full_map() -> Map[Str, Str] {
  let m0 := map.new()
  let m1 := map.set(m0, headers.h_authorization(), "Token abc==")
  let m2 := map.set(m1, headers.h_request_id(), "req-1")
  let m3 := map.set(m2, headers.h_correlation_id(), "corr-1")
  let m4 := map.set(m3, headers.h_from_country_code(), "NL")
  let m5 := map.set(m4, headers.h_from_party_id(), "TNM")
  let m6 := map.set(m5, headers.h_to_country_code(), "DE")
  map.set(m6, headers.h_to_party_id(), "BMW")
}

fn test_from_map_full() -> Result[Unit, Str] {
  let h := headers.from_map(full_map())
  if h.authorization == "Token abc=="
     and h.request_id == "req-1"
     and h.from_party.country_code == "NL"
     and h.to_party.party_id == "BMW" {
    pass()
  } else {
    fail("from_map missing fields")
  }
}

fn test_from_map_partial() -> Result[Unit, Str] {
  let m0 := map.new()
  let m1 := map.set(m0, headers.h_authorization(), "Token xyz")
  let h := headers.from_map(m1)
  if h.authorization == "Token xyz"
     and h.request_id == ""
     and str.is_empty(h.from_party.country_code) {
    pass()
  } else {
    fail("partial map should leave missing fields empty")
  }
}

# ---- Authorization extraction -----------------------------------

fn test_strip_token() -> Result[Unit, Str] {
  match headers.strip_token_prefix("Token abc==") {
    None    => fail("Token prefix should match"),
    Some(s) => assert_eq_str("abc==", s, "stripped token"),
  }
}

fn test_strip_token_bad_prefix() -> Result[Unit, Str] {
  match headers.strip_token_prefix("Bearer xyz") {
    None    => pass(),
    Some(_) => fail("Bearer prefix should not match"),
  }
}

fn test_strip_token_empty() -> Result[Unit, Str] {
  match headers.strip_token_prefix("") {
    None    => pass(),
    Some(_) => fail("empty authz should not match"),
  }
}

# ---- Predicates -------------------------------------------------

fn test_has_party_routing_true() -> Result[Unit, Str] {
  let h := headers.from_map(full_map())
  assert_true(headers.has_party_routing(h),
    "full quad should be considered routed")
}

fn test_has_party_routing_false() -> Result[Unit, Str] {
  let h := headers.from_map(map.new())
  assert_true(not headers.has_party_routing(h),
    "empty quad should not be considered routed")
}

# ---- Round-trip --------------------------------------------------

fn test_round_trip_to_map() -> Result[Unit, Str] {
  let h := headers.from_map(full_map())
  let m := headers.to_map(h)
  let h2 := headers.from_map(m)
  if h.authorization == h2.authorization
     and headers.has_party_routing(h2) {
    pass()
  } else {
    fail("round trip lost data")
  }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_from_map_full(),
    test_from_map_partial(),
    test_strip_token(),
    test_strip_token_bad_prefix(),
    test_strip_token_empty(),
    test_has_party_routing_true(),
    test_has_party_routing_false(),
    test_round_trip_to_map(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}
