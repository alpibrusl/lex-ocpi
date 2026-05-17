# lex-ocpi — top-level setup: bootstrap every OCPI table at once
#
# Call `setup_all(db)` once at startup. Each per-module `migrate`
# emits `CREATE TABLE IF NOT EXISTS` plus its indexes, so the whole
# call is idempotent.
#
# This bypasses lex-orm's version-based `m.apply(db, current,
# versions)` runner because that runner evolves a single
# ModelSchema across versions — it doesn't fit a multi-table
# schema like OCPI's (a v2=Sessions would diff against v1=Locations
# and emit nonsense ALTERs). When lex-orm grows multi-table
# migrations we can switch over.
#
# Effects: [sql].

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "./locations" as r_locs

import "./sessions" as r_sess

import "./cdrs" as r_cdrs

import "./tokens" as r_toks

import "./tariffs" as r_tars

fn setup_all(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  match r_locs.migrate(db) {
    Err(e) => Err(e),
    Ok(_) => match r_sess.migrate(db) {
      Err(e) => Err(e),
      Ok(_) => match r_cdrs.migrate(db) {
        Err(e) => Err(e),
        Ok(_) => match r_toks.migrate(db) {
          Err(e) => Err(e),
          Ok(_) => r_tars.migrate(db),
        },
      },
    },
  }
}
