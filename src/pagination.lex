# lex-ocpi — pagination helpers
#
# OCPI list endpoints (Locations, Sessions, CDRs, Tokens, Tariffs)
# all use the same `?offset=N&limit=M` query-string shape plus
# `X-Total-Count` and `Link` response headers. ocpi-python (and most
# CPO/eMSP impls) page by default with limit=50. This module centralises
# the parse + emit machinery so every list handler doesn't reinvent it.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.3 (Pagination)
#   OCPI 2.3.0 — Part I §4.3
#
# Effects: none.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.map"  as map

# ---- Page request -----------------------------------------------
#
# Inbound query: `?offset=N&limit=M`. Defaults: offset=0, limit=50.
# Per spec a server MAY cap limit; `clamp_limit` enforces an upper
# bound (typically 1000) and returns the effective limit.

type PageRequest = {
  offset :: Int,
  limit  :: Int,
}

fn defaults() -> PageRequest {
  { offset: 0, limit: 50 }
}

fn from_query(query :: Map[Str, Str]) -> PageRequest {
  let offset := parse_int_or(query, "offset", 0)
  let limit  := parse_int_or(query, "limit",  50)
  { offset: offset, limit: limit }
}

fn parse_int_or(query :: Map[Str, Str], key :: Str, default :: Int) -> Int {
  match map.get(query, key) {
    None    => default,
    Some(s) => match str.to_int(s) {
      None    => default,
      Some(n) => if n < 0 { 0 } else { n },
    },
  }
}

fn clamp_limit(req :: PageRequest, max :: Int) -> PageRequest
  examples {
    clamp_limit({ offset: 0, limit: 5000 }, 1000) => { offset: 0, limit: 1000 },
    clamp_limit({ offset: 10, limit: 50 }, 1000) => { offset: 10, limit: 50 },
  }
{
  if req.limit > max { { offset: req.offset, limit: max } }
  else { req }
}

# ---- Page response ----------------------------------------------
#
# A list handler's output: the slice of items + total count + the
# effective offset/limit (after clamping). The transport adapter
# turns this into response headers (`X-Total-Count`, `X-Limit`,
# `Link: <next>; rel="next"`).
#
# Items are JSON values (every OCPI list endpoint returns an array of
# pre-encoded objects), so we don't parameterise; downstream callers
# encode their domain values to `jv.Json` before paging.

import "lex-schema/json_value" as jv

type Page = {
  items  :: List[jv.Json],
  offset :: Int,
  limit  :: Int,
  total  :: Int,
}

fn paginate(all :: List[jv.Json], req :: PageRequest, total :: Int) -> Page {
  let limit  := req.limit
  let offset := req.offset
  let slice  := list_slice(all, offset, offset + limit)
  { items: slice, offset: offset, limit: limit, total: total }
}

# Take items[lo..hi) — inclusive of lo, exclusive of hi. Both bounds
# are clamped to `[0, len(items)]` so out-of-range indices just yield
# an empty slice rather than a panic.
fn list_slice(items :: List[jv.Json], lo :: Int, hi :: Int) -> List[jv.Json] {
  list_slice_loop(items, 0, lo, hi, [])
}

fn list_slice_loop(
  items :: List[jv.Json],
  i     :: Int,
  lo    :: Int,
  hi    :: Int,
  acc   :: List[jv.Json]
) -> List[jv.Json] {
  match list.head(items) {
    None       => acc,
    Some(head) => {
      let next := list.tail(items)
      let acc2 := if i >= lo and i < hi {
        list.concat(acc, [head])
      } else {
        acc
      }
      if i + 1 >= hi { acc2 }
      else { list_slice_loop(next, i + 1, lo, hi, acc2) }
    },
  }
}

# ---- Response headers -------------------------------------------
#
# Build the standard OCPI pagination headers as a Map[Str, Str].
# Pair with the transport adapter — it merges these into the HTTP
# response headers alongside the envelope JSON body.

fn headers(page :: Page, base_url :: Str) -> Map[Str, Str] {
  let m := map.set(map.new(),
    "x-total-count", int.to_str(page.total))
  let m1 := map.set(m, "x-limit", int.to_str(page.limit))
  let next_offset := page.offset + page.limit
  if next_offset >= page.total {
    m1
  } else {
    let next_url := build_next_url(base_url, next_offset, page.limit)
    map.set(m1, "link",
      str.concat("<", str.concat(next_url, ">; rel=\"next\"")))
  }
}

fn build_next_url(base :: Str, offset :: Int, limit :: Int) -> Str {
  str.concat(base,
    str.concat("?offset=",
      str.concat(int.to_str(offset),
        str.concat("&limit=", int.to_str(limit)))))
}

# ---- Predicates --------------------------------------------------

fn has_more(page :: Page) -> Bool
  examples {
    has_more({ items: [], offset: 0, limit: 50, total: 100 }) => true,
    has_more({ items: [], offset: 50, limit: 50, total: 100 }) => false,
  }
{
  page.offset + page.limit < page.total
}
