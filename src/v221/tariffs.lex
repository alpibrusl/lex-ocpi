# lex-ocpi — OCPI 2.2.1 Tariffs module
#
# A `Tariff` describes the pricing structure for a charging session
# at a given Location/Connector. The CPO ships tariffs to the eMSP
# so the driver app can show "this will cost X €" before plugging in.
# Tariffs are by far the most expressive object in OCPI — nested
# `TariffElement`s with `PriceComponent` arrays + per-element
# `TariffRestrictions`.
#
# Spec references:
#   OCPI 2.2.1 — Part III §11 (Tariffs module)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"    as en
import "./locations" as locs
import "./sessions"  as sess

# ---- PriceComponent ----------------------------------------------

fn price_component_schema() -> s.ModelSchema {
  {
    title: "PriceComponent",
    description: "OCPI 2.2.1 — PriceComponent",
    fields: [
      s.required_str("type",     [StrOneOf(en.all_tariff_dimension_type())]),
      s.required_float("price",  []),
      s.optional(s.required_float("vat", [])),
      s.required_int("step_size", [IntNonNegative]),
    ],
  }
}

# ---- TariffRestrictions ------------------------------------------

fn tariff_restrictions_schema() -> s.ModelSchema {
  {
    title: "TariffRestrictions",
    description: "OCPI 2.2.1 — TariffRestrictions",
    fields: [
      s.optional(s.required_str("start_time", [StrMaxLen(5)])),
      s.optional(s.required_str("end_time",   [StrMaxLen(5)])),
      s.optional(s.required_str("start_date", [StrMaxLen(10)])),
      s.optional(s.required_str("end_date",   [StrMaxLen(10)])),
      s.optional(s.required_float("min_kwh",     [])),
      s.optional(s.required_float("max_kwh",     [])),
      s.optional(s.required_float("min_current", [])),
      s.optional(s.required_float("max_current", [])),
      s.optional(s.required_float("min_power",   [])),
      s.optional(s.required_float("max_power",   [])),
      s.optional(s.required_int("min_duration",    [IntNonNegative])),
      s.optional(s.required_int("max_duration",    [IntNonNegative])),
      s.optional(s.required_array("day_of_week",
        KStr([StrOneOf(en.all_day_of_week())]), [])),
      s.optional(s.required_str("reservation",  [StrNonEmpty])),
    ],
  }
}

# ---- TariffElement -----------------------------------------------

fn tariff_element_schema() -> s.ModelSchema {
  {
    title: "TariffElement",
    description: "OCPI 2.2.1 — TariffElement",
    fields: [
      s.required_array("price_components",
        KObject(price_component_schema()), [ListNonEmpty]),
      s.optional(s.required_object("restrictions",
        tariff_restrictions_schema())),
    ],
  }
}

# ---- Tariff ------------------------------------------------------

fn tariff_schema() -> s.ModelSchema {
  {
    title: "Tariff",
    description: "OCPI 2.2.1 — Tariff object",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("currency",     [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_str("type", [StrOneOf(en.all_tariff_type())])),
      s.optional(s.required_array("tariff_alt_text",
        KObject(locs.display_text_schema()), [])),
      s.optional(s.required_str("tariff_alt_url", [StrMaxLen(255)])),
      s.optional(s.required_object("min_price",   sess.price_schema())),
      s.optional(s.required_object("max_price",   sess.price_schema())),
      s.required_array("elements", KObject(tariff_element_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("start_date_time", [StrNonEmpty])),
      s.optional(s.required_str("end_date_time",   [StrNonEmpty])),
      s.optional(s.required_object("energy_mix",   energy_mix_schema())),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

# ---- EnergyMix (minimal — pricing-only consumers can ignore) -----

fn energy_mix_schema() -> s.ModelSchema {
  {
    title: "EnergyMix",
    description: "OCPI 2.2.1 — EnergyMix (renewable / nuclear / fossil split)",
    fields: [
      s.required_bool("is_green_energy"),
      s.optional(s.required_array("energy_sources",
        KObject(energy_source_schema()), [])),
      s.optional(s.required_array("environ_impact",
        KObject(environ_impact_schema()), [])),
      s.optional(s.required_str("supplier_name",    [StrMaxLen(64)])),
      s.optional(s.required_str("energy_product_name", [StrMaxLen(64)])),
    ],
  }
}

fn energy_source_schema() -> s.ModelSchema {
  {
    title: "EnergySource",
    description: "OCPI 2.2.1 — EnergySource entry",
    fields: [
      s.required_str("source",     [StrNonEmpty]),
      s.required_float("percentage", []),
    ],
  }
}

fn environ_impact_schema() -> s.ModelSchema {
  {
    title: "EnvironmentalImpact",
    description: "OCPI 2.2.1 — EnvironmentalImpact entry",
    fields: [
      s.required_str("category",  [StrNonEmpty]),
      s.required_float("amount",    []),
    ],
  }
}

fn validate_tariff(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(tariff_schema(), j)
}
