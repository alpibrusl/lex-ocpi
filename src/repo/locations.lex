# lex-ocpi — `RepoSchema` + migration for ocpi_locations
#
# Wraps the canonical OCPI 2.2.1 Location schema with a lex-orm
# repo + DDL bootstrap. The Location object embeds EVSEs and
# Connectors as a nested JSON array — those are stored alongside
# the Location row (JSONB on Postgres, TEXT on SQLite), not in
# separate tables. That matches the wire format and avoids the
# join graph a CPO would otherwise need to maintain.
#
# Indexes:
#   - last_updated            (date-range filters on the list endpoint)
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

# Passthrough decoder. OCPI handlers operate on jv.Json end-to-end
# (validated by `s.validate(schema, j)` at ingress, persisted as
# JSON, emitted as JSON at egress), so a typed Lex record buys us
# little here. Swap for a typed `Location` decoder if downstream
# code wants to operate on records directly.
fn decode(j :: jv.Json) -> Result[jv.Json, se.Errors] {
  Ok(j)
}

# RepoSchema handle: schema is the canonical OCPI Location, table
# name overridden to `ocpi_locations` so it doesn't collide with
# other modules in a shared deployment.
fn repo() -> q.RepoSchema {
  q.with_table(q.for_schema(schema()), table_name())
}

fn indexes() -> List[m.DdlChange] {
  [m.add_index("idx_ocpi_locations_last_updated", ["last_updated"]), m.add_index("idx_ocpi_locations_country_party", ["country_code", "party_id"])]
}

# Idempotent CREATE TABLE + CREATE INDEX. Safe to call on every
# startup; lex-orm emits `IF NOT EXISTS` on both DDL paths.
fn migrate(db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  mig.run_ddl(db, table_name(), schema(), indexes())
}
