# lex-ocpi — `Repo[jv.Json]` + migration for ocpi_locations
#
# Wraps the OCPI 2.2.1 Location schema with a lex-orm `Repo[T]`
# (T = jv.Json since OCPI handlers operate on JSON end-to-end).
# Nested EVSEs / Connectors are stored alongside the Location row
# as JSONB/TEXT, not in separate tables — matches the wire format
# and avoids a maintenance-burdening join graph.
#
# Indexes:
#   - last_updated            (date-range filters on the list endpoint)
#   - country_code, party_id  (per-party Location listings)

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

# Passthrough decoder. Wire-side validation runs at request ingress
# (`s.validate(schema, j)`); persistence and egress also use jv.Json.
# A typed `Location` Lex record can replace this later without
# touching the table layout.
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

