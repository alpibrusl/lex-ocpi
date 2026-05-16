# lex-ocpi — token authorization (version-agnostic core)
#
# The `AuthorizationResult` ADT and the JSON ↔ ADT mapping are
# identical across OCPI 2.1.1 / 2.2.1 / 2.3.0 — the spec's
# `AllowedType` catalog is `ALLOWED | BLOCKED | EXPIRED | NO_CREDIT
# | NOT_ALLOWED` in every version. The per-version differences
# (URL shape, AuthorizationInfo schema details) live in
# `src/v211/authorize.lex` / `src/v221/authorize.lex` /
# `src/v230/authorize.lex`.
#
# Single nominal type also lets callers that mix versions (e.g.
# a hub or a multi-version peer) write one `match` over the result
# rather than branching on which version's variant they got.
#
# Spec references:
#   OCPI 2.2.1 — Part III §12.5.1 (AuthorizationInfo object)
#
# Effects: none.

import "std.str" as str

import "lex-schema/json_value" as jv

# Constant strings for the AllowedType enum. Stable across all three
# OCPI versions; mirrored in each `v<XX>/enums.lex` for the schema
# `StrOneOf(...)` validators — these are kept in sync with those.

fn allowed_str()     -> Str { "ALLOWED" }
fn blocked_str()     -> Str { "BLOCKED" }
fn expired_str()     -> Str { "EXPIRED" }
fn no_credit_str()   -> Str { "NO_CREDIT" }
fn not_allowed_str() -> Str { "NOT_ALLOWED" }

# ---- AuthorizationResult ----------------------------------------
#
# The variant tag carries the spec's `AllowedType` decision; the
# payload carries the *validated* AuthorizationInfo JSON, so callers
# can pull `token` / `location` / `authorization_reference` / `info`
# out of it without re-parsing. Single-payload variants match the
# `ClientError` / `HandlerResult` shape used elsewhere in lex-ocpi.

type AuthorizationResult =
    Allowed(jv.Json)
  | Blocked(jv.Json)
  | Expired(jv.Json)
  | NoCredit(jv.Json)
  | NotAllowed(jv.Json)

# Extract the underlying AuthorizationInfo JSON regardless of which
# branch fired. Useful for callers that just want the wire shape.
fn info(r :: AuthorizationResult) -> jv.Json {
  match r {
    Allowed(j)    => j,
    Blocked(j)    => j,
    Expired(j)    => j,
    NoCredit(j)   => j,
    NotAllowed(j) => j,
  }
}

# ---- Decoder ----------------------------------------------------
#
# Given an AuthorizationInfo JSON value (already passed
# `validate_authorization_info` — guaranteed to have an `allowed`
# string field), pick the right variant. Returns Err on:
#   - missing `allowed` field
#   - non-string `allowed` value
#   - unrecognised AllowedType value
#
# The redundancy with the schema validator is deliberate: the
# decoder is total even on unvalidated input so callers can decide
# whether to validate first.

fn decode(j :: jv.Json) -> Result[AuthorizationResult, Str] {
  match jv.get_field(j, "allowed") {
    None     => Err("AuthorizationInfo missing `allowed` field"),
    Some(av) => match jv.as_str(av) {
      None    => Err("AuthorizationInfo `allowed` is not a string"),
      Some(s) => decode_allowed_str(s, j),
    },
  }
}

fn decode_allowed_str(s :: Str, j :: jv.Json) -> Result[AuthorizationResult, Str] {
  if s == allowed_str()        { Ok(Allowed(j)) }
  else { if s == blocked_str()     { Ok(Blocked(j)) }
  else { if s == expired_str()     { Ok(Expired(j)) }
  else { if s == no_credit_str()   { Ok(NoCredit(j)) }
  else { if s == not_allowed_str() { Ok(NotAllowed(j)) }
  else { Err(str.concat("AuthorizationInfo `allowed` not in catalogue: ", s)) }
  } } } }
}

# ---- Encoder ----------------------------------------------------
#
# Pure inverse of `decode`: returns the embedded AuthorizationInfo
# JSON unchanged. Round-tripping `decode . encode` is the identity
# on validated input.

fn encode(r :: AuthorizationResult) -> jv.Json {
  info(r)
}
