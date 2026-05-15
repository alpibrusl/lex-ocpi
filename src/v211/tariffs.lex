# lex-ocpi — OCPI 2.1.1 Tariffs module
#
# 2.1.1 Tariff differs from 2.2.1:
#   - `tariff_alt_text` is required (not optional) — the field set
#     was tightened in 2.2
#   - no `type` enum (ad_hoc/profile_*/regular added in 2.2)
#   - no `start_date_time`/`end_date_time` validity window
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"     as en
import "./locations" as locs

# ---- PriceComponent ---------------------------------------------

fn price_component_schema() -> s.ModelSchema {
  {
    title: "PriceComponent",
    description: "OCPI 2.1.1 — PriceComponent",
    fields: [
      s.required_str("type",      [StrOneOf(en.all_tariff_dimension_type())]),
      s.required_float("price",   []),
      s.required_int("step_size", [IntNonNegative]),
    ],
  }
}

# ---- TariffRestrictions (smaller in 2.1.1) ----------------------

fn tariff_restrictions_schema() -> s.ModelSchema {
  {
    title: "TariffRestrictions",
    description: "OCPI 2.1.1 — TariffRestrictions",
    fields: [
      s.optional(s.required_str("start_time", [StrMaxLen(5)])),
      s.optional(s.required_str("end_time",   [StrMaxLen(5)])),
      s.optional(s.required_str("start_date", [StrMaxLen(10)])),
      s.optional(s.required_str("end_date",   [StrMaxLen(10)])),
      s.optional(s.required_float("min_kwh",     [])),
      s.optional(s.required_float("max_kwh",     [])),
      s.optional(s.required_float("min_power",   [])),
      s.optional(s.required_float("max_power",   [])),
      s.optional(s.required_int("min_duration", [IntNonNegative])),
      s.optional(s.required_int("max_duration", [IntNonNegative])),
      s.optional(s.required_array("day_of_week",
        KStr([StrOneOf(en.all_day_of_week())]), [])),
    ],
  }
}

# ---- TariffElement ----------------------------------------------

fn tariff_element_schema() -> s.ModelSchema {
  {
    title: "TariffElement",
    description: "OCPI 2.1.1 — TariffElement",
    fields: [
      s.required_array("price_components",
        KObject(price_component_schema()), [ListNonEmpty]),
      s.optional(s.required_object("restrictions",
        tariff_restrictions_schema())),
    ],
  }
}

# ---- Tariff -----------------------------------------------------

fn tariff_schema() -> s.ModelSchema {
  {
    title: "Tariff",
    description: "OCPI 2.1.1 — Tariff object",
    fields: [
      s.required_str("id",       [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("currency", [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("tariff_alt_text",
        KObject(locs.display_text_schema()), [])),
      s.optional(s.required_str("tariff_alt_url", [StrMaxLen(255)])),
      s.required_array("elements", KObject(tariff_element_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_object("energy_mix", locs.energy_mix_schema())),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_tariff(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(tariff_schema(), j)
}
