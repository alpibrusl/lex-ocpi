# lex-ocpi — `RepoSchema` + migration for ocpi_tokens
#
# A Token represents an authorisation credential issued by an
# eMSP to one of its drivers — typically an RFID card. The eMSP
# pushes its token list to the CPO; the CPO uses it to authorise
# StartTransaction at the charger.
#
# Indexes:
#   - last_updated  (date-range filters on the list endpoint)
#   - uid           (Authorize-on-demand lookup hits this column)
#
# Effects: [sql] for `migrate(db)`.

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "lex-orm/query" as q

import "lex-orm/migrate" as m

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "../v221/tokens" as toks

import "./migrations" as mig

fn table_name() -> Str {
  "ocpi_tokens"
}

fn schema() -> s.ModelSchema {
  toks.token_schema()
}

fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] {
  Ok(j)
}

fn repo() -> q.RepoSchema {
  q.with_table(q.for_schema(schema()), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_tokens_last_updated", ["last_updated"]), m.add_index("idx_ocpi_tokens_uid", ["uid"])]
}

fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
