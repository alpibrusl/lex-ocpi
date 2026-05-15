# lex-ocpi — OCPI role constants
#
# OCPI is a peer-to-peer protocol; every participating party
# declares one or more **roles** in its `CredentialsRole` records.
# The role determines which modules a party implements and which
# direction of each module it implements (sender vs receiver).
#
# Spec references:
#   OCPI 2.2.1 — Part I §3 (Terminology)
#   OCPI 2.3.0 — Part I §3
#
# Exposed as `fn () -> Str` constants (the wire spelling) plus an
# `all_roles()` catalog for `StrOneOf` validators. New roles
# introduced in later OCPI versions slot in here without breaking
# 2.2.1 callers.
#
# Effects: none.

import "std.list" as list

# ---- Role string constants ---------------------------------------
#
# CPO  — Charge Point Operator
# EMSP — eMobility Service Provider
# HUB  — OCPI hub (forwards module traffic between CPOs and EMSPs)
# NSP  — Navigation Service Provider (read-only Locations / Tariffs)
# OTHER — vendor extensions outside the spec's named roles
# SCSP — Smart Charging Service Provider
# PTP  — Payment Terminal Provider (OCPI 2.3.0+)

fn cpo()   -> Str { "CPO" }
fn emsp()  -> Str { "EMSP" }
fn hub()   -> Str { "HUB" }
fn nsp()   -> Str { "NSP" }
fn other() -> Str { "OTHER" }
fn scsp()  -> Str { "SCSP" }
fn ptp()   -> Str { "PTP" }

# ---- Bulk catalogs -----------------------------------------------
#
# `all_roles_v221` is the 2.2.1 surface; `all_roles_v230` adds PTP.
# Schemas pick the version-appropriate set via `StrOneOf`.

fn all_roles_v221() -> List[Str] {
  [cpo(), emsp(), hub(), nsp(), other(), scsp()]
}

fn all_roles_v230() -> List[Str] {
  [cpo(), emsp(), hub(), nsp(), other(), scsp(), ptp()]
}

fn all_roles() -> List[Str] { all_roles_v230() }
