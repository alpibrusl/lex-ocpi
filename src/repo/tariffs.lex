# lex-ocpi — `Repo[jv.Json]` + migration for ocpi_tariffs
#
# Indexes: last_updated

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "lex-orm/query" as q

import "lex-orm/migrate" as m

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "../v221/tariffs" as tars

import "./migrations" as mig

fn table_name() -> Str { "ocpi_tariffs" }

fn schema() -> s.ModelSchema { tars.tariff_schema() }

fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }

fn repo() -> q.Repo[jv.Json] {
  q.with_table(q.for_schema(schema(), decode), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_tariffs_last_updated", ["last_updated"])]
}

fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
