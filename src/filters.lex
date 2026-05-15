# lex-ocpi — list-endpoint filter helpers
#
# Every OCPI list endpoint (GET /locations, /sessions, /cdrs,
# /tariffs, /tokens) accepts `?date_from=ISO8601&date_to=ISO8601`
# query parameters that constrain the returned set to items whose
# `last_updated` falls in `[date_from, date_to)`. This module
# centralises the parse + apply machinery so every handler doesn't
# reinvent it.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4.3 (pagination + filters)
#   OCPI 2.3.0 — Part I §4.3
#
# DateTime values are compared lexicographically — ISO 8601 with a
# consistent timezone (Zulu / UTC) sorts correctly as strings. The
# library accepts any string the caller supplies; callers that need
# stricter validation (e.g. reject malformed dates) layer a
# lex-schema validator on top.
#
# Effects: none.

import "std.str"  as str
import "std.list" as list
import "std.map"  as map

import "lex-schema/json_value" as jv

# ---- DateRange parsed from a query map --------------------------

type DateRange = {
  date_from :: Option[Str],
  date_to   :: Option[Str],
}

fn from_query(query :: Map[Str, Str]) -> DateRange {
  { date_from: map.get(query, "date_from"),
    date_to:   map.get(query, "date_to") }
}

fn any() -> DateRange { { date_from: None, date_to: None } }

# ---- Apply the range over a list of `jv.Json` items -------------
#
# Items must carry a `last_updated` string field at the top level.
# Items missing the field are dropped (defensive — a real CPO never
# emits a Location/Session/CDR without `last_updated`).

fn apply(items :: List[jv.Json], range :: DateRange) -> List[jv.Json] {
  list.filter(items,
    fn (item :: jv.Json) -> Bool { in_range(item, range) })
}

fn in_range(item :: jv.Json, range :: DateRange) -> Bool {
  match jv.get_field(item, "last_updated") {
    None    => false,
    Some(v) => match jv.as_str(v) {
      None    => false,
      Some(ts) => above_lower(ts, range.date_from)
              and below_upper(ts, range.date_to),
    },
  }
}

fn above_lower(ts :: Str, lower :: Option[Str]) -> Bool
  examples {
    above_lower("2026-05-15", Some("2026-05-01")) => true,
    above_lower("2026-05-15", None) => true,
    above_lower("2026-04-30", Some("2026-05-01")) => false,
  }
{
  match lower {
    None    => true,
    Some(l) => str_ge(ts, l),
  }
}

fn below_upper(ts :: Str, upper :: Option[Str]) -> Bool
  examples {
    below_upper("2026-05-15", Some("2026-06-01")) => true,
    below_upper("2026-05-15", None) => true,
    below_upper("2026-06-01", Some("2026-06-01")) => false,
  }
{
  match upper {
    None    => true,
    Some(u) => str_lt(ts, u),
  }
}

# ---- Lexicographic comparison -----------------------------------
#
# ISO 8601 sortability is the whole reason we can compare these as
# raw strings. lex-lang's std.str doesn't expose a comparator yet,
# so we hand-roll a length-then-bytewise comparison. Correct for
# fixed-width ISO strings ("2026-05-15T10:00:00Z" vs
# "2026-05-15T10:00:00Z").

fn str_lt(a :: Str, b :: Str) -> Bool
  examples {
    str_lt("a", "b") => true,
    str_lt("b", "a") => false,
    str_lt("a", "a") => false,
  }
{
  cmp(a, b) == 0 - 1
}

fn str_ge(a :: Str, b :: Str) -> Bool
  examples {
    str_ge("b", "a") => true,
    str_ge("a", "a") => true,
    str_ge("a", "b") => false,
  }
{
  cmp(a, b) >= 0
}

# Returns `-1` if a<b, `0` if a==b, `1` if a>b. Compares byte-wise
# up to the shorter length; equal-prefix tiebroken by length.
fn cmp(a :: Str, b :: Str) -> Int {
  cmp_loop(a, b, 0)
}

fn cmp_loop(a :: Str, b :: Str, i :: Int) -> Int {
  let alen := str.len(a)
  let blen := str.len(b)
  if i >= alen and i >= blen {
    0
  } else { if i >= alen {
    0 - 1
  } else { if i >= blen {
    1
  } else {
    let ca := str.slice(a, i, i + 1)
    let cb := str.slice(b, i, i + 1)
    if ca == cb {
      cmp_loop(a, b, i + 1)
    } else { if ca < cb {
      0 - 1
    } else {
      1
    } }
  } } }
}
