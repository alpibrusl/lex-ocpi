# lex-ocpi — OCPI 2.3.0 ChargingProfiles module
#
# Wire shape unchanged from 2.2.1. Re-shipped under v230/ so a
# `lex audit --calls v230/chargingprofiles.*` query returns the
# right call-graph for the 2.3.0 surface.
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

# ---- ChargingRateUnit / ChargingProfileResultType ---------------

fn cru_w()  -> Str { "W" }
fn cru_a()  -> Str { "A" }
fn all_charging_rate_unit() -> List[Str] { [cru_w(), cru_a()] }

fn cpr_accepted() -> Str { "ACCEPTED" }
fn cpr_rejected() -> Str { "REJECTED" }
fn cpr_unknown()  -> Str { "UNKNOWN" }
fn all_charging_profile_result_type() -> List[Str] {
  [cpr_accepted(), cpr_rejected(), cpr_unknown()]
}

fn cprt_accepted()        -> Str { "ACCEPTED" }
fn cprt_not_supported()   -> Str { "NOT_SUPPORTED" }
fn cprt_rejected()        -> Str { "REJECTED" }
fn cprt_too_often()       -> Str { "TOO_OFTEN" }
fn cprt_unknown_session() -> Str { "UNKNOWN_SESSION" }
fn all_charging_profile_response_type() -> List[Str] {
  [cprt_accepted(), cprt_not_supported(), cprt_rejected(),
   cprt_too_often(), cprt_unknown_session()]
}

# ---- ChargingProfilePeriod / ChargingProfile --------------------

fn charging_profile_period_schema() -> s.ModelSchema {
  {
    title: "ChargingProfilePeriod",
    description: "OCPI 2.3.0 — one slice of a ChargingProfile",
    fields: [
      s.required_int("start_period", [IntNonNegative]),
      s.required_float("limit",      []),
    ],
  }
}

fn charging_profile_schema() -> s.ModelSchema {
  {
    title: "ChargingProfile",
    description: "OCPI 2.3.0 — ChargingProfile object",
    fields: [
      s.optional(s.required_str("start_date_time", [StrNonEmpty])),
      s.optional(s.required_int("duration", [IntPositive])),
      s.required_str("charging_rate_unit", [StrOneOf(all_charging_rate_unit())]),
      s.optional(s.required_float("min_charging_rate", [])),
      s.required_array("charging_profile_period",
        KObject(charging_profile_period_schema()), [ListNonEmpty]),
    ],
  }
}

fn validate_charging_profile(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(charging_profile_schema(), j)
}

# ---- ActiveChargingProfile / Set / response / result -----------

fn active_charging_profile_schema() -> s.ModelSchema {
  {
    title: "ActiveChargingProfile",
    description: "OCPI 2.3.0 — ActiveChargingProfile object",
    fields: [
      s.required_str("start_date_time", [StrNonEmpty]),
      s.required_object("charging_profile", charging_profile_schema()),
    ],
  }
}

fn validate_active_charging_profile(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(active_charging_profile_schema(), j)
}

fn set_charging_profile_schema() -> s.ModelSchema {
  {
    title: "SetChargingProfile",
    description: "OCPI 2.3.0 — SetChargingProfile PUT body",
    fields: [
      s.required_object("charging_profile", charging_profile_schema()),
      s.required_str("response_url", [StrNonEmpty, StrMaxLen(255)]),
    ],
  }
}

fn validate_set_charging_profile(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(set_charging_profile_schema(), j)
}

fn charging_profile_response_schema() -> s.ModelSchema {
  {
    title: "ChargingProfileResponse",
    description: "OCPI 2.3.0 — synchronous ChargingProfileResponse",
    fields: [
      s.required_str("result", [StrOneOf(all_charging_profile_response_type())]),
      s.required_int("timeout", [IntNonNegative]),
    ],
  }
}

fn validate_charging_profile_response(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(charging_profile_response_schema(), j)
}

fn charging_profile_result_schema() -> s.ModelSchema {
  {
    title: "ChargingProfileResult",
    description: "OCPI 2.3.0 — async ChargingProfileResult",
    fields: [
      s.required_str("result", [StrOneOf(all_charging_profile_result_type())]),
    ],
  }
}

fn validate_charging_profile_result(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(charging_profile_result_schema(), j)
}
