# lex-ocpi — shared DDL helpers for `src/repo/*`
#
# Each OCPI module file (`repo/locations.lex` etc.) ships its own
# `schema()` + `indexes()` + `migrate()` triple. The actual DDL
# execution is identical across modules; this file owns that
# plumbing.
#
# All statements are idempotent (`IF NOT EXISTS`), so `migrate(db)`
# is safe to call on every startup — no version-tracking dance.
#
# Effects: [sql] for `run_ddl` / `apply_indexes`.

import "std.list" as list

import "std.sql" as sql

import "lex-schema/schema" as s

import "lex-orm/migrate" as m

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

fn run_ddl(db :: conn.ConnDb, table :: Str, schema :: s.ModelSchema, indexes :: List[m.DdlChange]) -> [sql] Result[Unit, dbe.DbErr] {
  let create_sql := m.to_create_table_named(table, schema, db.dialect)
  match sql.exec(db.handle, create_sql, []) {
    Err(e) => Err(map_err(e)),
    Ok(_) => apply_indexes(db, table, indexes),
  }
}

fn apply_indexes(db :: conn.ConnDb, table :: Str, indexes :: List[m.DdlChange]) -> [sql] Result[Unit, dbe.DbErr] {
  list.fold(indexes, Ok(()), fn (acc :: Result[Unit, dbe.DbErr], ch :: m.DdlChange) -> [sql] Result[Unit, dbe.DbErr] {
    match acc {
      Err(e) => Err(e),
      Ok(_) => {
        let stmt := m.to_alter_table(table, [ch], db.dialect)
        match sql.exec(db.handle, stmt, []) {
          Err(e) => Err(map_err(e)),
          Ok(_) => Ok(()),
        }
      },
    }
  })
}

fn map_err(e :: SqlError) -> dbe.DbErr {
  dbe.sql_error(match e.code {
    None => "",
    Some(c) => c,
  }, e.message)
}

