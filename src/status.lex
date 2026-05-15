# lex-ocpi — OCPI status codes
#
# OCPI defines a fixed four-digit status code catalogue covering
# successes (1xxx), client errors (2xxx), server errors (3xxx), and
# hub errors (4xxx). Constants live here so handlers and middleware
# never inline raw integers at the call site (typos surface as a
# runtime envelope, not a typecheck failure).
#
# Spec references:
#   OCPI 2.2.1 — Part I §6 (Status codes)
#   OCPI 2.3.0 — Part I §6
#
# Every constant is exposed as `fn () -> Int` so callers reach for
# `status.success()`, not the literal `1000`. The string-form
# companion (for envelope `status_message`) lives next to each
# constant as `*_message`.
#
# Effects: none.

import "std.list" as list

# ---- 1xxx — Success ----------------------------------------------

fn success() -> Int { 1000 }
fn success_message() -> Str { "Success" }

# ---- 2xxx — Client errors ----------------------------------------

fn client_error()                        -> Int { 2000 }
fn invalid_or_missing_parameters()       -> Int { 2001 }
fn not_enough_information()              -> Int { 2002 }
fn unknown_location()                    -> Int { 2003 }
fn unknown_token()                       -> Int { 2004 }

# ---- 3xxx — Server errors ----------------------------------------

fn server_error()                        -> Int { 3000 }
fn unable_to_use_api()                   -> Int { 3001 }
fn unsupported_version()                 -> Int { 3002 }
fn no_matching_endpoints()               -> Int { 3003 }

# ---- 4xxx — Hub errors -------------------------------------------

fn hub_error()                           -> Int { 4000 }
fn missing_or_invalid_parameters()       -> Int { 4001 }
fn unknown_receiver()                    -> Int { 4002 }
fn timeout_on_forwarded_request()        -> Int { 4003 }
fn connection_problem()                  -> Int { 4004 }

# ---- Catalog -----------------------------------------------------
#
# `all_codes()` is the property-test surface — every status the
# library knows about. Useful for sanity checks ("every error code
# in `all_codes()` round-trips through `to_message`").

fn all_codes() -> List[Int] {
  [
    success(),
    client_error(),
    invalid_or_missing_parameters(),
    not_enough_information(),
    unknown_location(),
    unknown_token(),
    server_error(),
    unable_to_use_api(),
    unsupported_version(),
    no_matching_endpoints(),
    hub_error(),
    missing_or_invalid_parameters(),
    unknown_receiver(),
    timeout_on_forwarded_request(),
    connection_problem(),
  ]
}

# ---- Code → canonical message -----------------------------------
#
# Maps a known status code to the canonical spec wording. Unknown
# codes return the empty string so envelope encoding can omit the
# `status_message` field (per Part I §4.1.2).

fn to_message(code :: Int) -> Str
  examples {
    to_message(1000) => "Success",
    to_message(2003) => "Unknown Location",
    to_message(9999) => "",
  }
{
  if code == success()                          { success_message() }
  else { if code == client_error()              { "Generic client error" }
  else { if code == invalid_or_missing_parameters() { "Invalid or missing parameters" }
  else { if code == not_enough_information()    { "Not enough information" }
  else { if code == unknown_location()          { "Unknown Location" }
  else { if code == unknown_token()             { "Unknown Token" }
  else { if code == server_error()              { "Generic server error" }
  else { if code == unable_to_use_api()         { "Unable to use the client's API" }
  else { if code == unsupported_version()       { "Unsupported version" }
  else { if code == no_matching_endpoints()     { "No matching endpoints or expected endpoints missing" }
  else { if code == hub_error()                 { "Generic Hub error" }
  else { if code == missing_or_invalid_parameters() { "Missing or invalid parameters" }
  else { if code == unknown_receiver()          { "Unknown receiver" }
  else { if code == timeout_on_forwarded_request() { "Timeout on forwarded request" }
  else { if code == connection_problem()        { "Connection problem" }
  else                                          { "" }
  } } } } } } } } } } } } } } }
}

# ---- Predicates ---------------------------------------------------

fn is_success(code :: Int) -> Bool
  examples {
    is_success(1000) => true,
    is_success(2001) => false,
  }
{
  code >= 1000 && code < 2000
}

fn is_client_error(code :: Int) -> Bool {
  code >= 2000 && code < 3000
}

fn is_server_error(code :: Int) -> Bool {
  code >= 3000 && code < 4000
}

fn is_hub_error(code :: Int) -> Bool {
  code >= 4000 && code < 5000
}
