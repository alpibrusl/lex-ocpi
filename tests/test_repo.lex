# lex-ocpi — pure tests for the repo/* layer.
#
# Integration tests (CREATE → INSERT → SELECT → X-Total-Count
# round-trip on a real database) live elsewhere and need a live
# SQLite handle. The tests here verify the pieces that can be
# checked without [sql]: table-name conventions, index DDL
# composition, and SELECT plan SQL.

import "std.str" as str

import "std.list" as list

import "lex-orm/query" as q

import "lex-orm/migrate" as m

import "../src/repo/locations" as r_locs

import "../src/repo/sessions" as r_sess

import "../src/repo/cdrs" as r_cdrs

import "../src/repo/tokens" as r_toks

import "../src/repo/tariffs" as r_tars

import "../src/repo/paginated" as paged

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

# ---- table names ------------------------------------------------
fn locations_table_name() -> Result[Unit, Str] {
  check("ocpi_locations", r_locs.repo().table == "ocpi_locations")
}

fn sessions_table_name() -> Result[Unit, Str] {
  check("ocpi_sessions", r_sess.repo().table == "ocpi_sessions")
}

fn cdrs_table_name() -> Result[Unit, Str] {
  check("ocpi_cdrs", r_cdrs.repo().table == "ocpi_cdrs")
}

fn tokens_table_name() -> Result[Unit, Str] {
  check("ocpi_tokens", r_toks.repo().table == "ocpi_tokens")
}

fn tariffs_table_name() -> Result[Unit, Str] {
  check("ocpi_tariffs", r_tars.repo().table == "ocpi_tariffs")
}

# ---- migrations emit CREATE TABLE -------------------------------
fn locations_create_ddl_includes_create() -> Result[Unit, Str] {
  let ddl := m.to_create_table_named(r_locs.table_name(), r_locs.schema(), DbPostgres)
  check("CREATE TABLE ocpi_locations", str.contains(ddl, "ocpi_locations"))
}

fn sessions_create_ddl_includes_create() -> Result[Unit, Str] {
  let ddl := m.to_create_table_named(r_sess.table_name(), r_sess.schema(), DbPostgres)
  check("CREATE TABLE ocpi_sessions", str.contains(ddl, "CREATE TABLE"))
}

# ---- indexes ----------------------------------------------------
fn tokens_indexes_include_uid() -> Result[Unit, Str] {
  let found := list.fold(r_toks.indexes(), false, fn (acc :: Bool, ch :: m.DdlChange) -> Bool {
    match ch {
      AddIndex(idx) => acc or idx.name == "idx_ocpi_tokens_uid",
      _ => acc,
    }
  })
  check("tokens uid index", found)
}

fn locations_indexes_include_country_party() -> Result[Unit, Str] {
  let found := list.fold(r_locs.indexes(), false, fn (acc :: Bool, ch :: m.DdlChange) -> Bool {
    match ch {
      AddIndex(idx) => acc or idx.name == "idx_ocpi_locations_country_party",
      _ => acc,
    }
  })
  check("locations country_party index", found)
}

fn every_table_has_last_updated_index() -> Result[Unit, Str] {
  let all_indexes := list.concat(list.concat(list.concat(list.concat(r_locs.indexes(), r_sess.indexes()), r_cdrs.indexes()), r_toks.indexes()), r_tars.indexes())
  let last_updated_count := list.fold(all_indexes, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch {
      AddIndex(idx) => if str.contains(idx.name, "last_updated") {
        acc + 1
      } else {
        acc
      },
      _ => acc,
    }
  })
  check("5 last_updated indexes", last_updated_count == 5)
}

# ---- date-range predicate composes ------------------------------
fn date_range_both_bounds() -> Result[Unit, Str] {
  let sel := paged.apply_date_range(q.select(r_locs.repo()), { date_from: Some("2026-01-01"), date_to: Some("2027-01-01") })
  let plan := q.build_select(sel)
  check("date range both", str.contains(plan.sql, ">=") and str.contains(plan.sql, "<") and list.len(plan.params) == 2)
}

fn date_range_lower_only() -> Result[Unit, Str] {
  let sel := paged.apply_date_range(q.select(r_locs.repo()), { date_from: Some("2026-01-01"), date_to: None })
  let plan := q.build_select(sel)
  check("date range lower", str.contains(plan.sql, ">=") and list.len(plan.params) == 1)
}

fn date_range_none() -> Result[Unit, Str] {
  let sel := paged.apply_date_range(q.select(r_locs.repo()), { date_from: None, date_to: None })
  let plan := q.build_select(sel)
  check("date range none", list.len(plan.params) == 0)
}

fn suite() -> List[Result[Unit, Str]] {
  [locations_table_name(), sessions_table_name(), cdrs_table_name(), tokens_table_name(), tariffs_table_name(), locations_create_ddl_includes_create(), sessions_create_ddl_includes_create(), tokens_indexes_include_uid(), locations_indexes_include_country_party(), every_table_has_last_updated_index(), date_range_both_bounds(), date_range_lower_only(), date_range_none()]
}

fn run_all() -> Int {
  let failed := list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
  if failed > 0 {
    1 / 0
  } else {
    0
  }
}
