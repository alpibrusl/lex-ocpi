# lex-ocpi — pagination tests

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

import "../src/pagination" as p

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- Query parsing ----------------------------------------------

fn test_from_query_defaults() -> Result[Unit, Str] {
  let req := p.from_query(map.new())
  if req.offset == 0 and req.limit == 50 { pass() }
  else { fail("defaults should be offset=0, limit=50") }
}

fn test_from_query_explicit() -> Result[Unit, Str] {
  let q1 := map.set(map.new(), "offset", "100")
  let q  := map.set(q1, "limit", "25")
  let req := p.from_query(q)
  if req.offset == 100 and req.limit == 25 { pass() }
  else { fail("explicit offset/limit not parsed") }
}

fn test_from_query_garbage() -> Result[Unit, Str] {
  let q := map.set(map.new(), "offset", "not_a_number")
  let req := p.from_query(q)
  assert_eq_int(0, req.offset, "garbage offset should fall back to default")
}

fn test_from_query_negative() -> Result[Unit, Str] {
  let q := map.set(map.new(), "offset", "-5")
  let req := p.from_query(q)
  assert_eq_int(0, req.offset, "negative offset should clamp to 0")
}

# ---- clamp_limit ------------------------------------------------

fn test_clamp_limit_under() -> Result[Unit, Str] {
  let req := p.clamp_limit({ offset: 0, limit: 25 }, 1000)
  assert_eq_int(25, req.limit, "under-cap limit untouched")
}

fn test_clamp_limit_over() -> Result[Unit, Str] {
  let req := p.clamp_limit({ offset: 0, limit: 5000 }, 1000)
  assert_eq_int(1000, req.limit, "over-cap limit clamped to max")
}

# ---- paginate / list_slice -------------------------------------

fn items() -> List[jv.Json] {
  [
    JStr("a"), JStr("b"), JStr("c"),
    JStr("d"), JStr("e"), JStr("f"),
  ]
}

fn test_paginate_first_page() -> Result[Unit, Str] {
  let page := p.paginate(items(), { offset: 0, limit: 3 }, 6)
  if list.len(page.items) == 3 and page.total == 6 { pass() }
  else { fail("first page should have 3 items, total 6") }
}

fn test_paginate_offset() -> Result[Unit, Str] {
  let page := p.paginate(items(), { offset: 3, limit: 3 }, 6)
  if list.len(page.items) == 3 and page.offset == 3 { pass() }
  else { fail("offset page should have 3 items at offset 3") }
}

fn test_paginate_past_end() -> Result[Unit, Str] {
  let page := p.paginate(items(), { offset: 10, limit: 50 }, 6)
  assert_eq_int(0, list.len(page.items), "past-end page should be empty")
}

# ---- has_more ---------------------------------------------------

fn test_has_more_true() -> Result[Unit, Str] {
  assert_true(
    p.has_more({ items: [], offset: 0, limit: 50, total: 100 }),
    "should have more")
}

fn test_has_more_false() -> Result[Unit, Str] {
  assert_true(
    not p.has_more({ items: [], offset: 50, limit: 50, total: 100 }),
    "should not have more")
}

# ---- headers ----------------------------------------------------

fn test_headers_total_and_limit() -> Result[Unit, Str] {
  let hdrs := p.headers(
    { items: [], offset: 0, limit: 25, total: 100 },
    "https://cpo.example.com/locations")
  let total := match map.get(hdrs, "x-total-count") {
    None    => "",
    Some(v) => v,
  }
  if total == "100" { pass() } else { fail("x-total-count header wrong") }
}

fn test_headers_link_on_more() -> Result[Unit, Str] {
  let hdrs := p.headers(
    { items: [], offset: 0, limit: 25, total: 100 },
    "https://cpo.example.com/locations")
  match map.get(hdrs, "link") {
    None    => fail("link header should be present when more items remain"),
    Some(v) => if str.contains(v, "offset=25") { pass() }
               else { fail("link header should carry next offset") },
  }
}

fn test_headers_no_link_on_last() -> Result[Unit, Str] {
  let hdrs := p.headers(
    { items: [], offset: 75, limit: 25, total: 100 },
    "https://cpo.example.com/locations")
  match map.get(hdrs, "link") {
    None    => pass(),
    Some(_) => fail("link header should be absent on the last page"),
  }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_from_query_defaults(),
    test_from_query_explicit(),
    test_from_query_garbage(),
    test_from_query_negative(),
    test_clamp_limit_under(),
    test_clamp_limit_over(),
    test_paginate_first_page(),
    test_paginate_offset(),
    test_paginate_past_end(),
    test_has_more_true(),
    test_has_more_false(),
    test_headers_total_and_limit(),
    test_headers_link_on_more(),
    test_headers_no_link_on_last(),
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
