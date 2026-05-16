# lex-ocpi — OCPI 2.2.1 enum string constants
#
# Each OCPI enum is exposed as:
#   - one `fn name() -> Str` per member (the exact wire string),
#   - one `fn all_<enum>() -> List[Str]` of every member, used by
#     lex-schema validators (`StrOneOf(all_xxx())`) to constrain
#     fields to the legal set.
#
# Variant ADTs would be more type-safe, but several OCPI enums
# (`ConnectorType`, `Facility`, `TokenType`) are open in practice —
# new members ship in errata. Strings + an `all_*` validator give
# the same safety on the validation boundary while preserving
# extensibility.
#
# Spec references:
#   OCPI 2.2.1 — Part III (Module references) / Annex B (Data types)
#
# Effects: none.

import "std.list" as list

# ---- LocationType ------------------------------------------------

fn loc_on_street()           -> Str { "ON_STREET" }
fn loc_parking_garage()      -> Str { "PARKING_GARAGE" }
fn loc_underground_garage()  -> Str { "UNDERGROUND_GARAGE" }
fn loc_parking_lot()         -> Str { "PARKING_LOT" }
fn loc_other()               -> Str { "OTHER" }
fn loc_unknown()             -> Str { "UNKNOWN" }

fn all_location_type() -> List[Str] {
  [loc_on_street(), loc_parking_garage(), loc_underground_garage(),
   loc_parking_lot(), loc_other(), loc_unknown()]
}

# ---- ParkingType -------------------------------------------------

fn park_along_motorway()     -> Str { "ALONG_MOTORWAY" }
fn park_parking_garage()     -> Str { "PARKING_GARAGE" }
fn park_parking_lot()        -> Str { "PARKING_LOT" }
fn park_on_driveway()        -> Str { "ON_DRIVEWAY" }
fn park_on_street()          -> Str { "ON_STREET" }
fn park_underground_garage() -> Str { "UNDERGROUND_GARAGE" }

fn all_parking_type() -> List[Str] {
  [park_along_motorway(), park_parking_garage(), park_parking_lot(),
   park_on_driveway(), park_on_street(), park_underground_garage()]
}

# ---- Status (EVSE / Connector) -----------------------------------

fn evse_available()    -> Str { "AVAILABLE" }
fn evse_blocked()      -> Str { "BLOCKED" }
fn evse_charging()     -> Str { "CHARGING" }
fn evse_inoperative()  -> Str { "INOPERATIVE" }
fn evse_outoforder()   -> Str { "OUTOFORDER" }
fn evse_planned()      -> Str { "PLANNED" }
fn evse_removed()      -> Str { "REMOVED" }
fn evse_reserved()     -> Str { "RESERVED" }
fn evse_unknown()      -> Str { "UNKNOWN" }

fn all_status() -> List[Str] {
  [evse_available(), evse_blocked(), evse_charging(),
   evse_inoperative(), evse_outoforder(), evse_planned(),
   evse_removed(), evse_reserved(), evse_unknown()]
}

# ---- Capability --------------------------------------------------

fn cap_charging_profile_capable()       -> Str { "CHARGING_PROFILE_CAPABLE" }
fn cap_charging_preferences_capable()   -> Str { "CHARGING_PREFERENCES_CAPABLE" }
fn cap_chip_card_support()              -> Str { "CHIP_CARD_SUPPORT" }
fn cap_contactless_card_support()       -> Str { "CONTACTLESS_CARD_SUPPORT" }
fn cap_credit_card_payable()            -> Str { "CREDIT_CARD_PAYABLE" }
fn cap_debit_card_payable()             -> Str { "DEBIT_CARD_PAYABLE" }
fn cap_ped_terminal()                   -> Str { "PED_TERMINAL" }
fn cap_remote_start_stop_capable()      -> Str { "REMOTE_START_STOP_CAPABLE" }
fn cap_reservable()                     -> Str { "RESERVABLE" }
fn cap_rfid_reader()                    -> Str { "RFID_READER" }
fn cap_token_group_capable()            -> Str { "TOKEN_GROUP_CAPABLE" }
fn cap_unlock_capable()                 -> Str { "UNLOCK_CAPABLE" }

fn all_capability() -> List[Str] {
  [cap_charging_profile_capable(), cap_charging_preferences_capable(),
   cap_chip_card_support(), cap_contactless_card_support(),
   cap_credit_card_payable(), cap_debit_card_payable(),
   cap_ped_terminal(), cap_remote_start_stop_capable(),
   cap_reservable(), cap_rfid_reader(),
   cap_token_group_capable(), cap_unlock_capable()]
}

# ---- ConnectorType -----------------------------------------------
#
# OCPI 2.2.1 Annex B.5. The catalog grows; add new members at the
# tail and append to `all_connector_type()`.

fn ct_chademo()               -> Str { "CHADEMO" }
fn ct_chaoji()                -> Str { "CHAOJI" }
fn ct_domestic_a()            -> Str { "DOMESTIC_A" }
fn ct_domestic_b()            -> Str { "DOMESTIC_B" }
fn ct_domestic_c()            -> Str { "DOMESTIC_C" }
fn ct_domestic_d()            -> Str { "DOMESTIC_D" }
fn ct_domestic_e()            -> Str { "DOMESTIC_E" }
fn ct_domestic_f()            -> Str { "DOMESTIC_F" }
fn ct_domestic_g()            -> Str { "DOMESTIC_G" }
fn ct_domestic_h()            -> Str { "DOMESTIC_H" }
fn ct_domestic_i()            -> Str { "DOMESTIC_I" }
fn ct_domestic_j()            -> Str { "DOMESTIC_J" }
fn ct_domestic_k()            -> Str { "DOMESTIC_K" }
fn ct_domestic_l()            -> Str { "DOMESTIC_L" }
fn ct_iec_60309_2_single_16() -> Str { "IEC_60309_2_single_16" }
fn ct_iec_60309_2_three_16()  -> Str { "IEC_60309_2_three_16" }
fn ct_iec_60309_2_three_32()  -> Str { "IEC_60309_2_three_32" }
fn ct_iec_60309_2_three_64()  -> Str { "IEC_60309_2_three_64" }
fn ct_iec_62196_t1()          -> Str { "IEC_62196_T1" }
fn ct_iec_62196_t1_combo()    -> Str { "IEC_62196_T1_COMBO" }
fn ct_iec_62196_t2()          -> Str { "IEC_62196_T2" }
fn ct_iec_62196_t2_combo()    -> Str { "IEC_62196_T2_COMBO" }
fn ct_iec_62196_t3a()         -> Str { "IEC_62196_T3A" }
fn ct_iec_62196_t3c()         -> Str { "IEC_62196_T3C" }
fn ct_tesla_r()               -> Str { "TESLA_R" }
fn ct_tesla_s()               -> Str { "TESLA_S" }

fn all_connector_type() -> List[Str] {
  [ct_chademo(), ct_chaoji(),
   ct_domestic_a(), ct_domestic_b(), ct_domestic_c(), ct_domestic_d(),
   ct_domestic_e(), ct_domestic_f(), ct_domestic_g(), ct_domestic_h(),
   ct_domestic_i(), ct_domestic_j(), ct_domestic_k(), ct_domestic_l(),
   ct_iec_60309_2_single_16(), ct_iec_60309_2_three_16(),
   ct_iec_60309_2_three_32(), ct_iec_60309_2_three_64(),
   ct_iec_62196_t1(), ct_iec_62196_t1_combo(),
   ct_iec_62196_t2(), ct_iec_62196_t2_combo(),
   ct_iec_62196_t3a(), ct_iec_62196_t3c(),
   ct_tesla_r(), ct_tesla_s()]
}

# ---- ConnectorFormat ---------------------------------------------

fn cf_socket() -> Str { "SOCKET" }
fn cf_cable()  -> Str { "CABLE" }

fn all_connector_format() -> List[Str] {
  [cf_socket(), cf_cable()]
}

# ---- PowerType ---------------------------------------------------

fn pt_ac_1_phase() -> Str { "AC_1_PHASE" }
fn pt_ac_2_phase() -> Str { "AC_2_PHASE" }
fn pt_ac_2_phase_split() -> Str { "AC_2_PHASE_SPLIT" }
fn pt_ac_3_phase() -> Str { "AC_3_PHASE" }
fn pt_dc()         -> Str { "DC" }

fn all_power_type() -> List[Str] {
  [pt_ac_1_phase(), pt_ac_2_phase(), pt_ac_2_phase_split(),
   pt_ac_3_phase(), pt_dc()]
}

# ---- TokenType ---------------------------------------------------

fn tt_ad_hoc_user() -> Str { "AD_HOC_USER" }
fn tt_app_user()    -> Str { "APP_USER" }
fn tt_other()       -> Str { "OTHER" }
fn tt_rfid()        -> Str { "RFID" }

fn all_token_type() -> List[Str] {
  [tt_ad_hoc_user(), tt_app_user(), tt_other(), tt_rfid()]
}

# ---- WhitelistType -----------------------------------------------

fn wl_always()             -> Str { "ALWAYS" }
fn wl_allowed()            -> Str { "ALLOWED" }
fn wl_allowed_offline()    -> Str { "ALLOWED_OFFLINE" }
fn wl_never()              -> Str { "NEVER" }

fn all_whitelist_type() -> List[Str] {
  [wl_always(), wl_allowed(), wl_allowed_offline(), wl_never()]
}

# ---- AllowedType (Authorization) ---------------------------------

fn allow_allowed()        -> Str { "ALLOWED" }
fn allow_blocked()        -> Str { "BLOCKED" }
fn allow_expired()        -> Str { "EXPIRED" }
fn allow_no_credit()      -> Str { "NO_CREDIT" }
fn allow_not_allowed()    -> Str { "NOT_ALLOWED" }

fn all_allowed_type() -> List[Str] {
  [allow_allowed(), allow_blocked(), allow_expired(),
   allow_no_credit(), allow_not_allowed()]
}

# ---- SessionStatus -----------------------------------------------

fn ss_active()      -> Str { "ACTIVE" }
fn ss_completed()   -> Str { "COMPLETED" }
fn ss_invalid()     -> Str { "INVALID" }
fn ss_pending()     -> Str { "PENDING" }
fn ss_reservation() -> Str { "RESERVATION" }

fn all_session_status() -> List[Str] {
  [ss_active(), ss_completed(), ss_invalid(),
   ss_pending(), ss_reservation()]
}

# ---- AuthMethod (CDR / Session) ----------------------------------

fn am_auth_request() -> Str { "AUTH_REQUEST" }
fn am_command()      -> Str { "COMMAND" }
fn am_whitelist()    -> Str { "WHITELIST" }

fn all_auth_method() -> List[Str] {
  [am_auth_request(), am_command(), am_whitelist()]
}

# ---- CdrDimensionType --------------------------------------------

fn cdt_current()          -> Str { "CURRENT" }
fn cdt_energy()           -> Str { "ENERGY" }
fn cdt_energy_export()    -> Str { "ENERGY_EXPORT" }
fn cdt_energy_import()    -> Str { "ENERGY_IMPORT" }
fn cdt_max_current()      -> Str { "MAX_CURRENT" }
fn cdt_min_current()      -> Str { "MIN_CURRENT" }
fn cdt_max_power()        -> Str { "MAX_POWER" }
fn cdt_min_power()        -> Str { "MIN_POWER" }
fn cdt_parking_time()     -> Str { "PARKING_TIME" }
fn cdt_power()            -> Str { "POWER" }
fn cdt_reservation_time() -> Str { "RESERVATION_TIME" }
fn cdt_state_of_charge()  -> Str { "STATE_OF_CHARGE" }
fn cdt_time()             -> Str { "TIME" }

fn all_cdr_dimension_type() -> List[Str] {
  [cdt_current(), cdt_energy(), cdt_energy_export(), cdt_energy_import(),
   cdt_max_current(), cdt_min_current(), cdt_max_power(), cdt_min_power(),
   cdt_parking_time(), cdt_power(), cdt_reservation_time(),
   cdt_state_of_charge(), cdt_time()]
}

# ---- TariffDimensionType -----------------------------------------

fn tdt_energy()       -> Str { "ENERGY" }
fn tdt_flat()         -> Str { "FLAT" }
fn tdt_parking_time() -> Str { "PARKING_TIME" }
fn tdt_time()         -> Str { "TIME" }

fn all_tariff_dimension_type() -> List[Str] {
  [tdt_energy(), tdt_flat(), tdt_parking_time(), tdt_time()]
}

# ---- TariffType --------------------------------------------------

fn tt_ad_hoc_payment()         -> Str { "AD_HOC_PAYMENT" }
fn tt_profile_cheap()          -> Str { "PROFILE_CHEAP" }
fn tt_profile_fast()           -> Str { "PROFILE_FAST" }
fn tt_profile_green()          -> Str { "PROFILE_GREEN" }
fn tt_regular()                -> Str { "REGULAR" }

fn all_tariff_type() -> List[Str] {
  [tt_ad_hoc_payment(), tt_profile_cheap(),
   tt_profile_fast(), tt_profile_green(), tt_regular()]
}

# ---- CommandType -------------------------------------------------

fn cmd_cancel_reservation()       -> Str { "CANCEL_RESERVATION" }
fn cmd_reserve_now()              -> Str { "RESERVE_NOW" }
fn cmd_start_session()            -> Str { "START_SESSION" }
fn cmd_stop_session()             -> Str { "STOP_SESSION" }
fn cmd_unlock_connector()         -> Str { "UNLOCK_CONNECTOR" }

fn all_command_type() -> List[Str] {
  [cmd_cancel_reservation(), cmd_reserve_now(),
   cmd_start_session(), cmd_stop_session(), cmd_unlock_connector()]
}

# ---- CommandResponseType -----------------------------------------

fn cmdr_not_supported()    -> Str { "NOT_SUPPORTED" }
fn cmdr_rejected()         -> Str { "REJECTED" }
fn cmdr_accepted()         -> Str { "ACCEPTED" }
fn cmdr_unknown_session()  -> Str { "UNKNOWN_SESSION" }

fn all_command_response_type() -> List[Str] {
  [cmdr_not_supported(), cmdr_rejected(),
   cmdr_accepted(), cmdr_unknown_session()]
}

# ---- CommandResult -----------------------------------------------

fn cr_accepted()         -> Str { "ACCEPTED" }
fn cr_canceled_reservation() -> Str { "CANCELED_RESERVATION" }
fn cr_evse_occupied()    -> Str { "EVSE_OCCUPIED" }
fn cr_evse_inoperative() -> Str { "EVSE_INOPERATIVE" }
fn cr_failed()           -> Str { "FAILED" }
fn cr_not_supported()    -> Str { "NOT_SUPPORTED" }
fn cr_rejected()         -> Str { "REJECTED" }
fn cr_timeout()          -> Str { "TIMEOUT" }
fn cr_unknown_reservation() -> Str { "UNKNOWN_RESERVATION" }

fn all_command_result_type() -> List[Str] {
  [cr_accepted(), cr_canceled_reservation(), cr_evse_occupied(),
   cr_evse_inoperative(), cr_failed(), cr_not_supported(),
   cr_rejected(), cr_timeout(), cr_unknown_reservation()]
}

# ---- ReservationStatus -------------------------------------------

fn rs_accepted()           -> Str { "ACCEPTED" }
fn rs_faulted()            -> Str { "FAULTED" }
fn rs_occupied()           -> Str { "OCCUPIED" }
fn rs_rejected()           -> Str { "REJECTED" }
fn rs_unavailable()        -> Str { "UNAVAILABLE" }

fn all_reservation_status() -> List[Str] {
  [rs_accepted(), rs_faulted(), rs_occupied(),
   rs_rejected(), rs_unavailable()]
}

# ---- DayOfWeek (Tariff restrictions) -----------------------------

fn dow_monday()    -> Str { "MONDAY" }
fn dow_tuesday()   -> Str { "TUESDAY" }
fn dow_wednesday() -> Str { "WEDNESDAY" }
fn dow_thursday()  -> Str { "THURSDAY" }
fn dow_friday()    -> Str { "FRIDAY" }
fn dow_saturday()  -> Str { "SATURDAY" }
fn dow_sunday()    -> Str { "SUNDAY" }

fn all_day_of_week() -> List[Str] {
  [dow_monday(), dow_tuesday(), dow_wednesday(), dow_thursday(),
   dow_friday(), dow_saturday(), dow_sunday()]
}
