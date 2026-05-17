# lex-ocpi — `Repo[jv.Json]` for the ocpi_locations table
#
# Wraps the canonical OCPI 2.2.1 Location schema with a lex-orm
# repo and migration. The Location object embeds EVSEs and
# Connectors as a nested JSON array — those are stored alongside
# the Location row (JSONB on Postgres, TEXT on SQLite), not in
# separate tables. That matches the wire format and avoids the
# join graph a CPO would otherwise need to maintain.
#
# Indexes:
#   - last_updated      (date-range filters on the list endpoint)
#   - country_code, party_id  (per-party Location listings)
#
# Effects: [sql] for `migrate(db)`.

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "lex-orm/query" as q

import "lex-orm/migrate" as m

import "lex-orm/connection" as conn

import "lex-orm/error" as dbe

import "../v221/locations" as locs

import "./migrations" as mig

fn table_name() -> Str {
  "ocpi_locations"
}

fn schema() -> s.ModelSchema {
  locs.location_schema()
}

# Passthrough decoder. OCPI handlers operate on jv.Json end-to-end:
# the wire body is validated by `s.validate(schema, j)` at ingress,
# persisted as JSON, and returned as JSON at egress. A typed `Location`
# Lex record can be wired in later without touching the table layout.
fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] {
  Ok(j)
}

fn repo() -> q.Repo[jv.Json] {
  q.with_table(q.for_schema(schema(), decode), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_locations_last_updated", ["last_updated"]), m.add_index("idx_ocpi_locations_country_party", ["country_code", "party_id"])]
}

fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
