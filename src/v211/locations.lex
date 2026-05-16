# lex-ocpi — OCPI 2.1.1 Locations module
#
# 2.1.1 Locations differs from 2.2.1:
#   - no `country_code` / `party_id` on the top-level (those moved
#     into the route URL instead)
#   - no `publish` flag (always public)
#   - no `parking_type` (added in 2.2)
#   - `evse.uid` is the primary key (same as 2.2)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- GeoLocation ------------------------------------------------

fn geo_location_schema() -> s.ModelSchema {
  {
    title: "GeoLocation",
    description: "OCPI 2.1.1 — coordinates",
    fields: [
      s.required_str("latitude",  [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("longitude", [StrNonEmpty, StrMaxLen(11)]),
    ],
  }
}

# ---- DisplayText ------------------------------------------------

fn display_text_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.1.1 — multi-language string",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

# ---- StatusSchedule ---------------------------------------------

fn status_schedule_schema() -> s.ModelSchema {
  {
    title: "StatusSchedule",
    description: "OCPI 2.1.1 — scheduled EVSE status change",
    fields: [
      s.required_str("period_begin", [StrNonEmpty]),
      s.optional(s.required_str("period_end", [StrNonEmpty])),
      s.required_str("status",       [StrOneOf(en.all_status())]),
    ],
  }
}

# ---- Image ------------------------------------------------------

fn image_schema() -> s.ModelSchema {
  {
    title: "Image",
    description: "OCPI 2.1.1 — Image object",
    fields: [
      s.required_str("url",      [StrNonEmpty, StrMaxLen(255)]),
      s.optional(s.required_str("thumbnail", [StrMaxLen(255)])),
      s.required_str("category", [StrNonEmpty, StrMaxLen(20)]),
      s.required_str("type",     [StrNonEmpty, StrMaxLen(4)]),
      s.optional(s.required_int("width",  [IntPositive])),
      s.optional(s.required_int("height", [IntPositive])),
    ],
  }
}

# ---- BusinessDetails --------------------------------------------

fn business_details_schema() -> s.ModelSchema {
  {
    title: "BusinessDetails",
    description: "OCPI 2.1.1 — BusinessDetails",
    fields: [
      s.required_str("name",    [StrNonEmpty, StrMaxLen(100)]),
      s.optional(s.required_str("website", [StrMaxLen(255)])),
      s.optional(s.required_object("logo", image_schema())),
    ],
  }
}

# ---- Connector --------------------------------------------------

fn connector_schema() -> s.ModelSchema {
  {
    title: "Connector",
    description: "OCPI 2.1.1 — Connector object",
    fields: [
      s.required_str("id",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("standard",     [StrOneOf(en.all_connector_type())]),
      s.required_str("format",       [StrOneOf(en.all_connector_format())]),
      s.required_str("power_type",   [StrOneOf(en.all_power_type())]),
      s.required_int("voltage",      [IntPositive]),
      s.required_int("amperage",     [IntPositive]),
      s.optional(s.required_str("tariff_id", [StrMaxLen(36)])),
      s.optional(s.required_str("terms_and_conditions", [StrNonEmpty])),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_connector(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(connector_schema(), j)
}

# ---- EVSE -------------------------------------------------------

fn evse_schema() -> s.ModelSchema {
  {
    title: "EVSE",
    description: "OCPI 2.1.1 — EVSE object",
    fields: [
      s.required_str("uid",                 [StrNonEmpty, StrMaxLen(39)]),
      s.optional(s.required_str("evse_id",  [StrMaxLen(48)])),
      s.required_str("status",              [StrOneOf(en.all_status())]),
      s.optional(s.required_array("status_schedule",
        KObject(status_schedule_schema()), [])),
      s.optional(s.required_array("capabilities",
        KStr([StrOneOf(en.all_capability())]), [])),
      s.required_array("connectors",        KObject(connector_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("floor_level",       [StrMaxLen(4)])),
      s.optional(s.required_object("coordinates",    geo_location_schema())),
      s.optional(s.required_str("physical_reference", [StrMaxLen(16)])),
      s.optional(s.required_array("directions",
        KObject(display_text_schema()), [])),
      s.optional(s.required_array("parking_restrictions",
        KStr([StrNonEmpty]), [])),
      s.optional(s.required_array("images", KObject(image_schema()), [])),
      s.required_str("last_updated",        [StrNonEmpty]),
    ],
  }
}

fn validate_evse(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(evse_schema(), j)
}

# ---- Location ---------------------------------------------------
#
# 2.1.1 Location has `country` not `country_code`/`party_id` on the
# object itself — those are part of the URL path.

fn location_schema() -> s.ModelSchema {
  {
    title: "Location",
    description: "OCPI 2.1.1 — Location object",
    fields: [
      s.required_str("id",             [StrNonEmpty, StrMaxLen(39)]),
      s.required_str("type",           [StrOneOf(en.all_location_type())]),
      s.optional(s.required_str("name",        [StrMaxLen(255)])),
      s.required_str("address",        [StrNonEmpty, StrMaxLen(45)]),
      s.required_str("city",           [StrNonEmpty, StrMaxLen(45)]),
      s.required_str("postal_code",    [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("country",        [StrNonEmpty, StrMaxLen(3)]),
      s.required_object("coordinates", geo_location_schema()),
      s.optional(s.required_array("related_locations",
        KObject(geo_location_schema()), [])),
      s.optional(s.required_array("evses", KObject(evse_schema()), [])),
      s.optional(s.required_array("directions",
        KObject(display_text_schema()), [])),
      s.optional(s.required_object("operator",    business_details_schema())),
      s.optional(s.required_object("suboperator", business_details_schema())),
      s.optional(s.required_object("owner",       business_details_schema())),
      s.optional(s.required_array("facilities",   KStr([StrNonEmpty]), [])),
      s.required_str("time_zone",      [StrNonEmpty, StrMaxLen(255)]),
      s.optional(s.required_object("opening_times", opening_times_schema())),
      s.optional(s.required_bool("charging_when_closed")),
      s.optional(s.required_array("images",        KObject(image_schema()), [])),
      s.optional(s.required_object("energy_mix",   energy_mix_schema())),
      s.required_str("last_updated",   [StrNonEmpty]),
    ],
  }
}

fn validate_location(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(location_schema(), j)
}

# ---- OpeningTimes (compact embed) -------------------------------

fn opening_times_schema() -> s.ModelSchema {
  {
    title: "Hours",
    description: "OCPI 2.1.1 — Hours / OpeningTimes",
    fields: [
      s.optional(s.required_bool("twentyfourseven")),
      s.optional(s.required_array("regular_hours",
        KObject(regular_hours_schema()), [])),
      s.optional(s.required_array("exceptional_openings",
        KObject(exceptional_period_schema()), [])),
      s.optional(s.required_array("exceptional_closings",
        KObject(exceptional_period_schema()), [])),
    ],
  }
}

fn regular_hours_schema() -> s.ModelSchema {
  {
    title: "RegularHours",
    description: "OCPI 2.1.1 — RegularHours",
    fields: [
      s.required_int("weekday",     [IntNonNegative]),
      s.required_str("period_begin", [StrNonEmpty, StrMaxLen(5)]),
      s.required_str("period_end",   [StrNonEmpty, StrMaxLen(5)]),
    ],
  }
}

fn exceptional_period_schema() -> s.ModelSchema {
  {
    title: "ExceptionalPeriod",
    description: "OCPI 2.1.1 — ExceptionalPeriod",
    fields: [
      s.required_str("period_begin", [StrNonEmpty]),
      s.required_str("period_end",   [StrNonEmpty]),
    ],
  }
}

# ---- EnergyMix (minimal — embed-only for Location) --------------

fn energy_mix_schema() -> s.ModelSchema {
  {
    title: "EnergyMix",
    description: "OCPI 2.1.1 — EnergyMix",
    fields: [
      s.required_bool("is_green_energy"),
      s.optional(s.required_str("supplier_name",       [StrMaxLen(64)])),
      s.optional(s.required_str("energy_product_name", [StrMaxLen(64)])),
    ],
  }
}
