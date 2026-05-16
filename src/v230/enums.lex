# lex-ocpi — OCPI 2.3.0 enums
#
# 2.3.0 is a strict superset of 2.2.1's enum surface plus a handful
# of additions: DER (Distributed Energy Resources) capabilities,
# bidirectional charging modes, the Payments module. Most enums
# carry over identically. Where 2.3.0 only adds members at the tail,
# we expose both the v221 set (`all_*_v221()`) and the full v230 set
# (`all_*()`) so v2.2.1 schemas reused under v2.3.0 don't widen
# accidentally.
#
# Spec references:
#   OCPI 2.3.0 — Module reference
#
# Effects: none.

import "std.list" as list

# ---- LocationType (unchanged from 2.2.1) ------------------------

fn loc_on_street()          -> Str { "ON_STREET" }
fn loc_parking_garage()     -> Str { "PARKING_GARAGE" }
fn loc_underground_garage() -> Str { "UNDERGROUND_GARAGE" }
fn loc_parking_lot()        -> Str { "PARKING_LOT" }
fn loc_other()              -> Str { "OTHER" }
fn loc_unknown()            -> Str { "UNKNOWN" }

fn all_location_type() -> List[Str] {
  [loc_on_street(), loc_parking_garage(), loc_underground_garage(),
   loc_parking_lot(), loc_other(), loc_unknown()]
}

# ---- ParkingType ------------------------------------------------

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

# ---- EVSE Status (unchanged) ------------------------------------

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

# ---- Capability (2.2.1 set + DER / V2X / payment additions) -----

fn cap_charging_profile_capable()     -> Str { "CHARGING_PROFILE_CAPABLE" }
fn cap_charging_preferences_capable() -> Str { "CHARGING_PREFERENCES_CAPABLE" }
fn cap_chip_card_support()            -> Str { "CHIP_CARD_SUPPORT" }
fn cap_contactless_card_support()     -> Str { "CONTACTLESS_CARD_SUPPORT" }
fn cap_credit_card_payable()          -> Str { "CREDIT_CARD_PAYABLE" }
fn cap_debit_card_payable()           -> Str { "DEBIT_CARD_PAYABLE" }
fn cap_ped_terminal()                 -> Str { "PED_TERMINAL" }
fn cap_remote_start_stop_capable()    -> Str { "REMOTE_START_STOP_CAPABLE" }
fn cap_reservable()                   -> Str { "RESERVABLE" }
fn cap_rfid_reader()                  -> Str { "RFID_READER" }
fn cap_token_group_capable()          -> Str { "TOKEN_GROUP_CAPABLE" }
fn cap_unlock_capable()               -> Str { "UNLOCK_CAPABLE" }
# 2.3.0 additions
fn cap_iso_15118_2_plug_charge()      -> Str { "ISO_15118_2_PLUG_CHARGE" }
fn cap_iso_15118_20_plug_charge()     -> Str { "ISO_15118_20_PLUG_CHARGE" }
fn cap_start_session_connector_required() -> Str { "START_SESSION_CONNECTOR_REQUIRED" }

fn all_capability() -> List[Str] {
  [cap_charging_profile_capable(), cap_charging_preferences_capable(),
   cap_chip_card_support(), cap_contactless_card_support(),
   cap_credit_card_payable(), cap_debit_card_payable(),
   cap_ped_terminal(), cap_remote_start_stop_capable(),
   cap_reservable(), cap_rfid_reader(),
   cap_token_group_capable(), cap_unlock_capable(),
   cap_iso_15118_2_plug_charge(),
   cap_iso_15118_20_plug_charge(),
   cap_start_session_connector_required()]
}

# ---- ConnectorType (2.2.1 + chaoji + couple of additions) -------

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
# 2.3.0 additions
fn ct_nema_5_20()             -> Str { "NEMA_5_20" }
fn ct_nema_6_30()             -> Str { "NEMA_6_30" }
fn ct_nema_6_50()             -> Str { "NEMA_6_50" }
fn ct_nema_10_30()            -> Str { "NEMA_10_30" }
fn ct_nema_10_50()            -> Str { "NEMA_10_50" }
fn ct_nema_14_30()            -> Str { "NEMA_14_30" }
fn ct_nema_14_50()            -> Str { "NEMA_14_50" }

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
   ct_tesla_r(), ct_tesla_s(),
   ct_nema_5_20(), ct_nema_6_30(), ct_nema_6_50(),
   ct_nema_10_30(), ct_nema_10_50(), ct_nema_14_30(), ct_nema_14_50()]
}

# ---- ConnectorFormat / PowerType (unchanged) --------------------

fn cf_socket() -> Str { "SOCKET" }
fn cf_cable()  -> Str { "CABLE" }
fn all_connector_format() -> List[Str] { [cf_socket(), cf_cable()] }

fn pt_ac_1_phase()        -> Str { "AC_1_PHASE" }
fn pt_ac_2_phase()        -> Str { "AC_2_PHASE" }
fn pt_ac_2_phase_split()  -> Str { "AC_2_PHASE_SPLIT" }
fn pt_ac_3_phase()        -> Str { "AC_3_PHASE" }
fn pt_dc()                -> Str { "DC" }
fn all_power_type() -> List[Str] {
  [pt_ac_1_phase(), pt_ac_2_phase(), pt_ac_2_phase_split(),
   pt_ac_3_phase(), pt_dc()]
}

# ---- TokenType / WhitelistType / AllowedType --------------------

fn tt_ad_hoc_user() -> Str { "AD_HOC_USER" }
fn tt_app_user()    -> Str { "APP_USER" }
fn tt_other()       -> Str { "OTHER" }
fn tt_rfid()        -> Str { "RFID" }
fn all_token_type() -> List[Str] {
  [tt_ad_hoc_user(), tt_app_user(), tt_other(), tt_rfid()]
}

fn wl_always()          -> Str { "ALWAYS" }
fn wl_allowed()         -> Str { "ALLOWED" }
fn wl_allowed_offline() -> Str { "ALLOWED_OFFLINE" }
fn wl_never()           -> Str { "NEVER" }
fn all_whitelist_type() -> List[Str] {
  [wl_always(), wl_allowed(), wl_allowed_offline(), wl_never()]
}

fn allow_allowed()     -> Str { "ALLOWED" }
fn allow_blocked()     -> Str { "BLOCKED" }
fn allow_expired()     -> Str { "EXPIRED" }
fn allow_no_credit()   -> Str { "NO_CREDIT" }
fn allow_not_allowed() -> Str { "NOT_ALLOWED" }
fn all_allowed_type() -> List[Str] {
  [allow_allowed(), allow_blocked(), allow_expired(),
   allow_no_credit(), allow_not_allowed()]
}

# ---- SessionStatus / AuthMethod ---------------------------------

fn ss_active()      -> Str { "ACTIVE" }
fn ss_completed()   -> Str { "COMPLETED" }
fn ss_invalid()     -> Str { "INVALID" }
fn ss_pending()     -> Str { "PENDING" }
fn ss_reservation() -> Str { "RESERVATION" }
fn all_session_status() -> List[Str] {
  [ss_active(), ss_completed(), ss_invalid(),
   ss_pending(), ss_reservation()]
}

fn am_auth_request() -> Str { "AUTH_REQUEST" }
fn am_command()      -> Str { "COMMAND" }
fn am_whitelist()    -> Str { "WHITELIST" }
fn all_auth_method() -> List[Str] {
  [am_auth_request(), am_command(), am_whitelist()]
}

# ---- CdrDimensionType (2.3.0 adds V2X import/export pair) -------

fn cdt_current()           -> Str { "CURRENT" }
fn cdt_energy()            -> Str { "ENERGY" }
fn cdt_energy_export()     -> Str { "ENERGY_EXPORT" }
fn cdt_energy_import()     -> Str { "ENERGY_IMPORT" }
fn cdt_max_current()       -> Str { "MAX_CURRENT" }
fn cdt_min_current()       -> Str { "MIN_CURRENT" }
fn cdt_max_power()         -> Str { "MAX_POWER" }
fn cdt_min_power()         -> Str { "MIN_POWER" }
fn cdt_parking_time()      -> Str { "PARKING_TIME" }
fn cdt_power()             -> Str { "POWER" }
fn cdt_reservation_time()  -> Str { "RESERVATION_TIME" }
fn cdt_state_of_charge()   -> Str { "STATE_OF_CHARGE" }
fn cdt_time()              -> Str { "TIME" }

fn all_cdr_dimension_type() -> List[Str] {
  [cdt_current(), cdt_energy(), cdt_energy_export(), cdt_energy_import(),
   cdt_max_current(), cdt_min_current(), cdt_max_power(), cdt_min_power(),
   cdt_parking_time(), cdt_power(), cdt_reservation_time(),
   cdt_state_of_charge(), cdt_time()]
}

# ---- TariffDimensionType / TariffType ---------------------------

fn tdt_energy()       -> Str { "ENERGY" }
fn tdt_flat()         -> Str { "FLAT" }
fn tdt_parking_time() -> Str { "PARKING_TIME" }
fn tdt_time()         -> Str { "TIME" }
fn all_tariff_dimension_type() -> List[Str] {
  [tdt_energy(), tdt_flat(), tdt_parking_time(), tdt_time()]
}

fn tt_ad_hoc_payment() -> Str { "AD_HOC_PAYMENT" }
fn tt_profile_cheap()  -> Str { "PROFILE_CHEAP" }
fn tt_profile_fast()   -> Str { "PROFILE_FAST" }
fn tt_profile_green()  -> Str { "PROFILE_GREEN" }
fn tt_regular()        -> Str { "REGULAR" }
fn all_tariff_type() -> List[Str] {
  [tt_ad_hoc_payment(), tt_profile_cheap(),
   tt_profile_fast(), tt_profile_green(), tt_regular()]
}

# ---- CommandType / CommandResponseType / CommandResult ----------

fn cmd_cancel_reservation() -> Str { "CANCEL_RESERVATION" }
fn cmd_reserve_now()        -> Str { "RESERVE_NOW" }
fn cmd_start_session()      -> Str { "START_SESSION" }
fn cmd_stop_session()       -> Str { "STOP_SESSION" }
fn cmd_unlock_connector()   -> Str { "UNLOCK_CONNECTOR" }
fn all_command_type() -> List[Str] {
  [cmd_cancel_reservation(), cmd_reserve_now(),
   cmd_start_session(), cmd_stop_session(), cmd_unlock_connector()]
}

fn cmdr_not_supported()   -> Str { "NOT_SUPPORTED" }
fn cmdr_rejected()        -> Str { "REJECTED" }
fn cmdr_accepted()        -> Str { "ACCEPTED" }
fn cmdr_unknown_session() -> Str { "UNKNOWN_SESSION" }
fn all_command_response_type() -> List[Str] {
  [cmdr_not_supported(), cmdr_rejected(),
   cmdr_accepted(), cmdr_unknown_session()]
}

# ---- DayOfWeek --------------------------------------------------

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

# ---- 2.3.0 — PaymentCurrency / PaymentStatus / Reference --------

fn ps_pending()   -> Str { "PENDING" }
fn ps_succeeded() -> Str { "SUCCEEDED" }
fn ps_failed()    -> Str { "FAILED" }
fn ps_refunded()  -> Str { "REFUNDED" }
fn ps_disputed()  -> Str { "DISPUTED" }

fn all_payment_status() -> List[Str] {
  [ps_pending(), ps_succeeded(), ps_failed(),
   ps_refunded(), ps_disputed()]
}

fn pm_credit_card()    -> Str { "CREDIT_CARD" }
fn pm_debit_card()     -> Str { "DEBIT_CARD" }
fn pm_chip_card()      -> Str { "CHIP_CARD" }
fn pm_contactless()    -> Str { "CONTACTLESS" }
fn pm_ad_hoc()         -> Str { "AD_HOC" }
fn pm_token()          -> Str { "TOKEN" }
fn pm_other()          -> Str { "OTHER" }

fn all_payment_method() -> List[Str] {
  [pm_credit_card(), pm_debit_card(), pm_chip_card(),
   pm_contactless(), pm_ad_hoc(), pm_token(), pm_other()]
}
