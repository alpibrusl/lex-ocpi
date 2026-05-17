# lex-ocpi — `RepoSchema` + migration for ocpi_tariffs
#
# A Tariff describes the pricing structure for a charging session
# at a given Location/Connector. The CPO ships tariffs to the eMSP
# so a driver app can show "this will cost X €" before plugging in.
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

import "../v221/tariffs" as tars

import "./migrations" as mig

fn table_name() -> Str {
  "ocpi_tariffs"
}

fn schema() -> s.ModelSchema {
  tars.tariff_schema()
}

fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] {
  Ok(j)
}

fn repo() -> q.RepoSchema {
  q.with_table(q.for_schema(schema()), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_tariffs_last_updated", ["last_updated"])]
}

fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
