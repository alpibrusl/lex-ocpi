# lex-ocpi — date-range filter tests

import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

import "../src/filters" as f

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- from_query ------------------------------------------------

fn test_from_query_empty() -> Result[Unit, Str] {
  let r := f.from_query(map.new())
  match r.date_from {
    None    => pass(),
    Some(_) => fail("empty query should yield date_from=None"),
  }
}

fn test_from_query_both() -> Result[Unit, Str] {
  let q := map.set(
    map.set(map.new(), "date_from", "2026-05-01T00:00:00Z"),
    "date_to",   "2026-06-01T00:00:00Z")
  let r := f.from_query(q)
  match r.date_from {
    None    => fail("date_from missing"),
    Some(s) => if s == "2026-05-01T00:00:00Z" { pass() }
               else { fail("date_from value wrong") },
  }
}

# ---- apply over a list ------------------------------------------

fn item(ts :: Str) -> jv.Json {
  JObj([("last_updated", JStr(ts))])
}

fn test_apply_no_bounds() -> Result[Unit, Str] {
  let items := [item("2026-04-01"), item("2026-05-15"), item("2026-06-01")]
  let kept := f.apply(items, f.any())
  assert_eq_int(3, list.len(kept), "no bounds keeps everything")
}

fn test_apply_lower_only() -> Result[Unit, Str] {
  let items := [item("2026-04-01"), item("2026-05-15"), item("2026-06-01")]
  let r := { date_from: Some("2026-05-01"), date_to: None }
  let kept := f.apply(items, r)
  assert_eq_int(2, list.len(kept),
    "lower bound 2026-05-01 should keep 2 of 3")
}

fn test_apply_upper_only() -> Result[Unit, Str] {
  let items := [item("2026-04-01"), item("2026-05-15"), item("2026-06-01")]
  let r := { date_from: None, date_to: Some("2026-06-01") }
  let kept := f.apply(items, r)
  assert_eq_int(2, list.len(kept),
    "upper bound 2026-06-01 (exclusive) should keep 2 of 3")
}

fn test_apply_both_bounds() -> Result[Unit, Str] {
  let items := [
    item("2026-04-01"),
    item("2026-05-15"),
    item("2026-06-01"),
    item("2026-07-01"),
  ]
  let r := { date_from: Some("2026-05-01"),
             date_to:   Some("2026-07-01") }
  let kept := f.apply(items, r)
  assert_eq_int(2, list.len(kept), "[05-01, 07-01) keeps 2 of 4")
}

fn test_apply_no_last_updated() -> Result[Unit, Str] {
  let items := [
    JObj([("id", JStr("no-timestamp"))]),
    item("2026-05-15"),
  ]
  let kept := f.apply(items, f.any())
  assert_eq_int(1, list.len(kept),
    "items lacking last_updated should be dropped")
}

# ---- str_lt / str_ge spot checks --------------------------------

fn test_str_lt_basic() -> Result[Unit, Str] {
  assert_true(f.str_lt("2026-05-01", "2026-05-15"), "str_lt basic")
}

fn test_str_ge_equal() -> Result[Unit, Str] {
  assert_true(f.str_ge("2026-05-15", "2026-05-15"), "str_ge on equal")
}

fn test_str_ge_different_length() -> Result[Unit, Str] {
  # Length tiebreak: "abc" > "ab"
  assert_true(f.str_ge("abc", "ab"), "longer prefix-match string is ge")
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_from_query_empty(),
    test_from_query_both(),
    test_apply_no_bounds(),
    test_apply_lower_only(),
    test_apply_upper_only(),
    test_apply_both_bounds(),
    test_apply_no_last_updated(),
    test_str_lt_basic(),
    test_str_ge_equal(),
    test_str_ge_different_length(),
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
