# lex-ocpi — `Repo[jv.Json]` for the ocpi_sessions table
#
# Sessions are the live record of an in-progress (or just-finished)
# charge. They ship from CPO to eMSP for real-time UI; once
# closed, the corresponding CDR carries the immutable billing
# record (see `cdrs.lex`).
#
# Indexes:
#   - last_updated  (date-range filters on the list endpoint)
#
# Effects: [sql] for `migrate(db)`.

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "lex-orm/query" as q

import "lex-orm/migrate" as m

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "../v221/sessions" as sess

import "./migrations" as mig

fn table_name() -> Str {
  "ocpi_sessions"
}

fn schema() -> s.ModelSchema {
  sess.session_schema()
}

fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] {
  Ok(j)
}

fn repo() -> q.Repo[jv.Json] {
  q.with_table(q.for_schema(schema(), decode), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_sessions_last_updated", ["last_updated"])]
}

fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
