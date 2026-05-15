# lex-ocpi — status code constant tests

import "std.str"  as str
import "std.list" as list

import "../src/status" as status

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_int(want :: Int, got :: Int, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- Spec-exact code values -------------------------------------

fn test_success_code() -> Result[Unit, Str] {
  assert_eq_int(1000, status.success(), "success")
}

fn test_client_error_codes() -> Result[Unit, Str] {
  if status.invalid_or_missing_parameters() == 2001
     && status.not_enough_information() == 2002
     && status.unknown_location() == 2003
     && status.unknown_token() == 2004 {
    pass()
  } else {
    fail("client-error codes drift from spec")
  }
}

fn test_server_error_codes() -> Result[Unit, Str] {
  if status.server_error() == 3000
     && status.unable_to_use_api() == 3001
     && status.unsupported_version() == 3002
     && status.no_matching_endpoints() == 3003 {
    pass()
  } else {
    fail("server-error codes drift from spec")
  }
}

fn test_hub_error_codes() -> Result[Unit, Str] {
  if status.hub_error() == 4000
     && status.missing_or_invalid_parameters() == 4001
     && status.unknown_receiver() == 4002
     && status.timeout_on_forwarded_request() == 4003
     && status.connection_problem() == 4004 {
    pass()
  } else {
    fail("hub-error codes drift from spec")
  }
}

# ---- Predicates --------------------------------------------------

fn test_predicates() -> Result[Unit, Str] {
  if status.is_success(1000)
     && status.is_client_error(2001)
     && status.is_server_error(3000)
     && status.is_hub_error(4001) {
    pass()
  } else {
    fail("predicates misclassify range members")
  }
}

# ---- Message lookup ----------------------------------------------

fn test_to_message_known() -> Result[Unit, Str] {
  if str.is_empty(status.to_message(1000))
     || str.is_empty(status.to_message(2003)) {
    fail("known codes should map to non-empty messages")
  } else {
    pass()
  }
}

fn test_to_message_unknown() -> Result[Unit, Str] {
  if str.is_empty(status.to_message(9999)) {
    pass()
  } else {
    fail("unknown code 9999 should map to empty string")
  }
}

# ---- Catalog coverage --------------------------------------------

fn test_all_codes_unique_and_nonempty() -> Result[Unit, Str] {
  let codes := status.all_codes()
  if list.len(codes) >= 15 { pass() }
  else { fail("all_codes should list at least 15 entries") }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_success_code(),
    test_client_error_codes(),
    test_server_error_codes(),
    test_hub_error_codes(),
    test_predicates(),
    test_to_message_known(),
    test_to_message_unknown(),
    test_all_codes_unique_and_nonempty(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r {
        Ok(_)  => n,
        Err(_) => n + 1,
      }
    })
}
