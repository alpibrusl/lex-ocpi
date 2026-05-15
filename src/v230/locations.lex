# lex-ocpi — OCPI 2.3.0 Locations module
#
# Same wire shape as 2.2.1 Locations, but the enum sets widen to
# cover the 2.3.0 additions (ISO_15118_2_PLUG_CHARGE,
# ISO_15118_20_PLUG_CHARGE, NEMA_5_20 / 6_30 / 14_50, …).
# Duplicating the schemas rather than re-exporting v221's so the
# `lex audit --calls StrOneOf` surface lists the wider sets directly.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- GeoLocation / DisplayText / Image / BusinessDetails --------

fn geo_location_schema() -> s.ModelSchema {
  {
    title: "GeoLocation",
    description: "OCPI 2.3.0 — coordinates",
    fields: [
      s.required_str("latitude",  [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("longitude", [StrNonEmpty, StrMaxLen(11)]),
    ],
  }
}

fn display_text_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.3.0 — multi-language string",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

fn image_schema() -> s.ModelSchema {
  {
    title: "Image",
    description: "OCPI 2.3.0 — Image object",
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

fn business_details_schema() -> s.ModelSchema {
  {
    title: "BusinessDetails",
    description: "OCPI 2.3.0 — BusinessDetails embedded in a Location",
    fields: [
      s.required_str("name",    [StrNonEmpty, StrMaxLen(100)]),
      s.optional(s.required_str("website", [StrMaxLen(255)])),
      s.optional(s.required_object("logo", image_schema())),
    ],
  }
}

# ---- StatusSchedule ---------------------------------------------

fn status_schedule_schema() -> s.ModelSchema {
  {
    title: "StatusSchedule",
    description: "OCPI 2.3.0 — scheduled EVSE status change",
    fields: [
      s.required_str("period_begin", [StrNonEmpty]),
      s.optional(s.required_str("period_end", [StrNonEmpty])),
      s.required_str("status",       [StrOneOf(en.all_status())]),
    ],
  }
}

# ---- Connector --------------------------------------------------

fn connector_schema() -> s.ModelSchema {
  {
    title: "Connector",
    description: "OCPI 2.3.0 — Connector object (with V2X / ISO 15118-20 capabilities)",
    fields: [
      s.required_str("id",                    [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("standard",              [StrOneOf(en.all_connector_type())]),
      s.required_str("format",                [StrOneOf(en.all_connector_format())]),
      s.required_str("power_type",            [StrOneOf(en.all_power_type())]),
      s.required_int("max_voltage",           [IntPositive]),
      s.required_int("max_amperage",          [IntPositive]),
      s.optional(s.required_int("max_electric_power", [IntPositive])),
      s.optional(s.required_array("tariff_ids",
        KStr([StrNonEmpty, StrMaxLen(36)]), [])),
      s.optional(s.required_str("terms_and_conditions", [StrNonEmpty])),
      s.required_str("last_updated",          [StrNonEmpty]),
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
    description: "OCPI 2.3.0 — EVSE object",
    fields: [
      s.required_str("uid",                  [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("evse_id",   [StrMaxLen(48)])),
      s.required_str("status",               [StrOneOf(en.all_status())]),
      s.optional(s.required_array("status_schedule",
        KObject(status_schedule_schema()), [])),
      s.optional(s.required_array("capabilities",
        KStr([StrOneOf(en.all_capability())]), [])),
      s.required_array("connectors",         KObject(connector_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("floor_level",       [StrMaxLen(4)])),
      s.optional(s.required_object("coordinates",    geo_location_schema())),
      s.optional(s.required_str("physical_reference",[StrMaxLen(16)])),
      s.optional(s.required_array("directions",
        KObject(display_text_schema()), [])),
      s.optional(s.required_array("parking_restrictions",
        KStr([StrNonEmpty]), [])),
      s.optional(s.required_array("images",
        KObject(image_schema()), [])),
      s.required_str("last_updated",         [StrNonEmpty]),
    ],
  }
}

fn validate_evse(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(evse_schema(), j)
}

# ---- Location ---------------------------------------------------

fn location_schema() -> s.ModelSchema {
  {
    title: "Location",
    description: "OCPI 2.3.0 — Location object",
    fields: [
      s.required_str("country_code",   [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",       [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",             [StrNonEmpty, StrMaxLen(36)]),
      s.required_bool("publish"),
      s.optional(s.required_str("name",        [StrMaxLen(255)])),
      s.required_str("address",        [StrNonEmpty, StrMaxLen(45)]),
      s.required_str("city",           [StrNonEmpty, StrMaxLen(45)]),
      s.optional(s.required_str("postal_code", [StrMaxLen(10)])),
      s.optional(s.required_str("state",       [StrMaxLen(20)])),
      s.required_str("country",        [StrNonEmpty, StrMaxLen(3)]),
      s.required_object("coordinates", geo_location_schema()),
      s.optional(s.required_str("parking_type",
        [StrOneOf(en.all_parking_type())])),
      s.required_array("evses",        KObject(evse_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_object("operator",    business_details_schema())),
      s.optional(s.required_object("suboperator", business_details_schema())),
      s.optional(s.required_object("owner",       business_details_schema())),
      s.required_str("time_zone",      [StrNonEmpty, StrMaxLen(255)]),
      s.optional(s.required_bool("charging_when_closed")),
      s.optional(s.required_array("images",
        KObject(image_schema()), [])),
      s.required_str("last_updated",   [StrNonEmpty]),
    ],
  }
}

fn validate_location(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(location_schema(), j)
}
