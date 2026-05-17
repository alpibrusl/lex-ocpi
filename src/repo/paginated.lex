# lex-ocpi — list_paginated helper combining lex-orm with the
# OCPI pagination + date-range filter idioms.
#
# Every OCPI list endpoint takes `?offset=N&limit=M&date_from=...&
# date_to=...`. This file owns the cross-cutting plumbing: apply
# the date range as a WHERE clause, page via SQL `LIMIT/OFFSET`,
# count the total for `X-Total-Count`, and wrap the result in a
# `pagination.Page`.

import "lex-schema/json_value" as jv

import "lex-orm/query" as q

import "lex-orm/predicate" as p

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "../pagination" as pg

import "../filters" as ft

# Layer an optional date-range predicate over `last_updated`.
# Bounds are `[date_from, date_to)` per OCPI 2.2.1 §4.3.
fn apply_date_range[T](sel :: q.SelectQuery[T], range :: ft.DateRange) -> q.SelectQuery[T] {
  let with_lo := match range.date_from {
    None => sel,
    Some(d) => q.where_clause(sel, p.gte("last_updated", PStr(d))),
  }
  match range.date_to {
    None => with_lo,
    Some(d) => q.where_clause(with_lo, p.lt("last_updated", PStr(d))),
  }
}

# Paginated list with date-range filter. Returns a `pagination.Page`
# carrying the slice for this page and the total row count (consumed
# by `X-Total-Count`).
fn list_paginated(repo :: q.Repo[jv.Json], db :: conn.ConnDb, req :: pg.PageRequest, range :: ft.DateRange) -> [sql] Result[pg.Page, dbe.DbErr] {
  let base := q.select(repo)
  let filtered := apply_date_range(base, range)
  let paged := q.offset(q.limit(q.order_by(filtered, "last_updated", Asc), req.limit), req.offset)
  match q.run_select(paged, db) {
    Err(e) => Err(e),
    Ok(items) => match q.run_count(filtered, db) {
      Err(e) => Err(e),
      Ok(total) => Ok({ items: items, offset: req.offset, limit: req.limit, total: total }),
    },
  }
}
