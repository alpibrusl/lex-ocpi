# lex-ocpi — OCPI 2.2.1 Sessions module
#
# Sessions describe a single charging period: when it started, the
# token authorising it, the EVSE / connector used, and (if active)
# the running kWh / cost. The CPO ships sessions to the eMSP for
# live status; the corresponding CDR ships once the session ends
# (see `cdrs.lex`).
#
# Spec references:
#   OCPI 2.2.1 — Part III §9 (Sessions module)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- CdrToken (also used by CDRs) --------------------------------
#
# A `CdrToken` is the OCPI-side reference to the token used to start
# the session. Different from a full `Token`: only the fields the
# Sessions / CDRs modules need.

fn cdr_token_schema() -> s.ModelSchema {
  {
    title: "CdrToken",
    description: "OCPI 2.2.1 — CdrToken (token reference in a session/CDR)",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("uid",          [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("type",         [StrOneOf(en.all_token_type())]),
      s.required_str("contract_id",  [StrNonEmpty, StrMaxLen(36)]),
    ],
  }
}

# ---- CdrDimension (used by both Sessions and CDRs) ---------------

fn cdr_dimension_schema() -> s.ModelSchema {
  {
    title: "CdrDimension",
    description: "OCPI 2.2.1 — CdrDimension (one entry in a ChargingPeriod)",
    fields: [
      s.required_str("type",   [StrOneOf(en.all_cdr_dimension_type())]),
      s.required_float("volume", []),
    ],
  }
}

# ---- ChargingPeriod ----------------------------------------------

fn charging_period_schema() -> s.ModelSchema {
  {
    title: "ChargingPeriod",
    description: "OCPI 2.2.1 — ChargingPeriod (one billing slice of a session)",
    fields: [
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_array("dimensions",    KObject(cdr_dimension_schema()),
                       [ListNonEmpty]),
      s.optional(s.required_str("tariff_id", [StrNonEmpty, StrMaxLen(36)])),
    ],
  }
}

# ---- Price -------------------------------------------------------

fn price_schema() -> s.ModelSchema {
  {
    title: "Price",
    description: "OCPI 2.2.1 — Price (excl. and incl. VAT)",
    fields: [
      s.required_float("excl_vat", []),
      s.optional(s.required_float("incl_vat", [])),
    ],
  }
}

# ---- Session -----------------------------------------------------

fn session_schema() -> s.ModelSchema {
  {
    title: "Session",
    description: "OCPI 2.2.1 — Session object",
    fields: [
      s.required_str("country_code",       [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",           [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",                 [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("start_date_time",    [StrNonEmpty]),
      s.optional(s.required_str("end_date_time", [StrNonEmpty])),
      s.required_float("kwh",              []),
      s.required_object("cdr_token",       cdr_token_schema()),
      s.required_str("auth_method",        [StrOneOf(en.all_auth_method())]),
      s.optional(s.required_str("authorization_reference",
        [StrNonEmpty, StrMaxLen(36)])),
      s.required_str("location_id",        [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("evse_uid",           [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("connector_id",       [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("meter_id",[StrMaxLen(255)])),
      s.required_str("currency",           [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_array("charging_periods",
        KObject(charging_period_schema()), [])),
      s.optional(s.required_object("total_cost", price_schema())),
      s.required_str("status",             [StrOneOf(en.all_session_status())]),
      s.required_str("last_updated",       [StrNonEmpty]),
    ],
  }
}

fn validate_session(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(session_schema(), j)
}

# ---- ChargingPreferences (eMSP → CPO, PUT) -----------------------

fn charging_preferences_schema() -> s.ModelSchema {
  {
    title: "ChargingPreferences",
    description: "OCPI 2.2.1 — ChargingPreferences (user-driver request)",
    fields: [
      s.required_str("profile_type",       [StrNonEmpty, StrMaxLen(255)]),
      s.optional(s.required_str("departure_time", [StrNonEmpty])),
      s.optional(s.required_float("energy_need",  [])),
      s.optional(s.required_bool("discharge_allowed")),
    ],
  }
}

fn validate_charging_preferences(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(charging_preferences_schema(), j)
}
