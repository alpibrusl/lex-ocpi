# lex-ocpi — OCPI 2.3.0 Tariffs module
#
# Wire shape unchanged from 2.2.1; the enum widening on
# `TariffDimensionType` and `TariffType` is captured in `enums.lex`.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums"     as en
import "./locations" as locs
import "./sessions"  as sess

# ---- PriceComponent ---------------------------------------------

fn price_component_schema() -> s.ModelSchema {
  {
    title: "PriceComponent",
    description: "OCPI 2.3.0 — PriceComponent",
    fields: [
      s.required_str("type",     [StrOneOf(en.all_tariff_dimension_type())]),
      s.required_float("price",  []),
      s.optional(s.required_float("vat", [])),
      s.required_int("step_size", [IntNonNegative]),
    ],
  }
}

# ---- TariffRestrictions -----------------------------------------

fn tariff_restrictions_schema() -> s.ModelSchema {
  {
    title: "TariffRestrictions",
    description: "OCPI 2.3.0 — TariffRestrictions",
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
      s.optional(s.required_int("min_duration", [IntNonNegative])),
      s.optional(s.required_int("max_duration", [IntNonNegative])),
      s.optional(s.required_array("day_of_week",
        KStr([StrOneOf(en.all_day_of_week())]), [])),
      s.optional(s.required_str("reservation", [StrNonEmpty])),
    ],
  }
}

# ---- TariffElement ----------------------------------------------

fn tariff_element_schema() -> s.ModelSchema {
  {
    title: "TariffElement",
    description: "OCPI 2.3.0 — TariffElement",
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
    description: "OCPI 2.3.0 — Tariff object",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("currency",     [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_str("type", [StrOneOf(en.all_tariff_type())])),
      s.optional(s.required_array("tariff_alt_text",
        KObject(locs.display_text_schema()), [])),
      s.optional(s.required_str("tariff_alt_url", [StrMaxLen(255)])),
      s.optional(s.required_object("min_price", sess.price_schema())),
      s.optional(s.required_object("max_price", sess.price_schema())),
      s.required_array("elements", KObject(tariff_element_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("start_date_time", [StrNonEmpty])),
      s.optional(s.required_str("end_date_time",   [StrNonEmpty])),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_tariff(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(tariff_schema(), j)
}
