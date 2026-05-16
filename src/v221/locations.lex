# lex-ocpi — OCPI 2.2.1 Locations module
#
# Schemas + datatypes for the Locations module. A `Location` is a
# physical site that hosts one or more `EVSE`s; each `EVSE` is a
# single charging point with one or more `Connector`s (different
# plug shapes / power types). The CPO side ships Locations to
# eMSPs; eMSPs consume the catalogue to drive routing / pricing
# UIs.
#
# Wire shape (top level):
#
#   Location {
#     country_code, party_id, id, publish,
#     name?, address, city, postal_code?, state?, country,
#     coordinates, related_locations?, parking_type?,
#     evses, directions?, operator?, suboperator?, owner?,
#     facilities?, time_zone, opening_times?, charging_when_closed?,
#     images?, energy_mix?, last_updated
#   }
#
# Spec references:
#   OCPI 2.2.1 — Part III §8 (Locations module)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- GeoLocation -------------------------------------------------

fn geo_location_schema() -> s.ModelSchema {
  {
    title: "GeoLocation",
    description: "OCPI 2.2.1 — coordinates of the location",
    fields: [
      s.required_str("latitude",  [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("longitude", [StrNonEmpty, StrMaxLen(11)]),
    ],
  }
}

# ---- AdditionalGeoLocation ---------------------------------------

fn additional_geo_location_schema() -> s.ModelSchema {
  {
    title: "AdditionalGeoLocation",
    description: "OCPI 2.2.1 — additional GeoLocation with name",
    fields: [
      s.required_str("latitude",  [StrNonEmpty, StrMaxLen(10)]),
      s.required_str("longitude", [StrNonEmpty, StrMaxLen(11)]),
      s.optional(s.required_object("name", display_text_schema())),
    ],
  }
}

# ---- DisplayText (used in multiple objects) ----------------------

fn display_text_schema() -> s.ModelSchema {
  {
    title: "DisplayText",
    description: "OCPI 2.2.1 — multi-language string",
    fields: [
      s.required_str("language", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("text",     [StrNonEmpty, StrMaxLen(512)]),
    ],
  }
}

# ---- StatusSchedule ----------------------------------------------

fn status_schedule_schema() -> s.ModelSchema {
  {
    title: "StatusSchedule",
    description: "OCPI 2.2.1 — scheduled EVSE status change",
    fields: [
      s.required_str("period_begin", [StrNonEmpty]),
      s.optional(s.required_str("period_end", [StrNonEmpty])),
      s.required_str("status",       [StrOneOf(en.all_status())]),
    ],
  }
}

# ---- Connector ---------------------------------------------------
#
# The most granular hardware element: one physical plug.

fn connector_schema() -> s.ModelSchema {
  {
    title: "Connector",
    description: "OCPI 2.2.1 — Connector object",
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

# ---- EVSE --------------------------------------------------------
#
# An `EVSE` is a single charge point that hosts one or more
# Connectors. The wire `evse_id` (eMI3) is optional; the OCPI `uid`
# is the primary key.

fn evse_schema() -> s.ModelSchema {
  {
    title: "EVSE",
    description: "OCPI 2.2.1 — EVSE object",
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

# ---- Image -------------------------------------------------------

fn image_schema() -> s.ModelSchema {
  {
    title: "Image",
    description: "OCPI 2.2.1 — Image object",
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

# ---- BusinessDetails (Operator / Suboperator / Owner) ------------

fn business_details_schema() -> s.ModelSchema {
  {
    title: "BusinessDetails",
    description: "OCPI 2.2.1 — BusinessDetails embedded in a Location",
    fields: [
      s.required_str("name",    [StrNonEmpty, StrMaxLen(100)]),
      s.optional(s.required_str("website", [StrMaxLen(255)])),
      s.optional(s.required_object("logo", image_schema())),
    ],
  }
}

# ---- Location ----------------------------------------------------

fn location_schema() -> s.ModelSchema {
  {
    title: "Location",
    description: "OCPI 2.2.1 — Location object",
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
      s.optional(s.required_array("related_locations",
        KObject(additional_geo_location_schema()), [])),
      s.optional(s.required_str("parking_type",
        [StrOneOf(en.all_parking_type())])),
      s.required_array("evses",        KObject(evse_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_array("directions",
        KObject(display_text_schema()), [])),
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
