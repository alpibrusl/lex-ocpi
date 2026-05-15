# lex-ocpi — OCPI module identifier constants
#
# An OCPI implementation advertises which modules it supports via
# the version detail endpoint (`GET /<version>/`); each module
# carries a wire-exact identifier string. Constants here cover the
# union across 2.1.1 / 2.2.1 / 2.3.0; the per-version `all_*`
# catalogs select the version-appropriate subset.
#
# Spec references:
#   OCPI 2.2.1 — Part I §6.2 (Module Identifiers)
#   OCPI 2.3.0 — Part I §6.2
#
# Configuration modules (cdrs / credentials / hubclientinfo /
# locations / sessions / tariffs / tokens / commands / chargingprofiles
# / payments) determine the endpoint catalog of a version-detail
# response. The constants are paired with `interface_role.lex`'s
# Sender/Receiver constants to fully describe an endpoint entry.
#
# Effects: none.

import "std.list" as list

# ---- Always-on configuration modules -----------------------------

fn credentials() -> Str { "credentials" }
fn versions()    -> Str { "versions" }

# ---- Functional modules ------------------------------------------

fn cdrs()              -> Str { "cdrs" }
fn chargingprofiles()  -> Str { "chargingprofiles" }
fn commands()          -> Str { "commands" }
fn hubclientinfo()     -> Str { "hubclientinfo" }
fn locations()         -> Str { "locations" }
fn sessions()          -> Str { "sessions" }
fn tariffs()           -> Str { "tariffs" }
fn tokens()            -> Str { "tokens" }

# ---- OCPI 2.3.0 additions ----------------------------------------

fn payments() -> Str { "payments" }

# ---- Bulk catalogs -----------------------------------------------
#
# Per-version module sets. The Credentials module is implicit (every
# OCPI peer ships it), but it appears here too so the version-detail
# `endpoints` array can list it explicitly.

fn all_v211() -> List[Str] {
  [
    credentials(),
    cdrs(),
    commands(),
    locations(),
    sessions(),
    tariffs(),
    tokens(),
  ]
}

fn all_v221() -> List[Str] {
  [
    credentials(),
    cdrs(),
    chargingprofiles(),
    commands(),
    hubclientinfo(),
    locations(),
    sessions(),
    tariffs(),
    tokens(),
  ]
}

fn all_v230() -> List[Str] {
  [
    credentials(),
    cdrs(),
    chargingprofiles(),
    commands(),
    hubclientinfo(),
    locations(),
    payments(),
    sessions(),
    tariffs(),
    tokens(),
  ]
}

fn all_modules() -> List[Str] { all_v230() }
