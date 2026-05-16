# lex-ocpi — Versions module tests

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "../src/versions"        as versions
import "../src/interface_role"  as iface
import "../src/module_id"       as mid

fn pass() -> Result[Unit, Str] { Ok(()) }
fn fail(why :: Str) -> Result[Unit, Str] { Err(why) }

fn assert_eq_str(want :: Str, got :: Str, label :: Str) -> Result[Unit, Str] {
  if want == got { pass() } else { fail(label) }
}

fn assert_true(b :: Bool, label :: Str) -> Result[Unit, Str] {
  if b { pass() } else { fail(label) }
}

# ---- Version-number constants -----------------------------------

fn test_version_constants() -> Result[Unit, Str] {
  if versions.v211() == "2.1.1"
     and versions.v221() == "2.2.1"
     and versions.v230() == "2.3.0" {
    pass()
  } else {
    fail("version constants drift")
  }
}

# ---- Endpoint encoding ------------------------------------------

fn test_endpoint_sender() -> Result[Unit, Str] {
  let e := versions.endpoint_sender(mid.locations(),
    "https://example.com/ocpi/cpo/2.2.1/locations")
  if e.role == iface.sender() { pass() }
  else { fail("endpoint_sender role should be SENDER") }
}

fn test_endpoint_receiver() -> Result[Unit, Str] {
  let e := versions.endpoint_receiver(mid.credentials(),
    "https://example.com/ocpi/cpo/2.2.1/credentials")
  if e.role == iface.receiver() { pass() }
  else { fail("endpoint_receiver role should be RECEIVER") }
}

fn test_endpoint_to_json_shape() -> Result[Unit, Str] {
  let e := versions.endpoint_sender(mid.locations(),
    "https://example.com/ocpi/cpo/2.2.1/locations")
  let raw := jv.stringify(versions.endpoint_to_json(e))
  assert_true(
    str.contains(raw, "\"identifier\":\"locations\"")
      and str.contains(raw, "\"role\":\"SENDER\"")
      and str.contains(raw, "\"url\":\"https://example.com/ocpi/cpo/2.2.1/locations\""),
    "endpoint JSON shape")
}

# ---- VersionDetail building -------------------------------------

fn test_detail_to_json() -> Result[Unit, Str] {
  let d := versions.detail(versions.v221(),
    versions.standard_cpo_v221_endpoints("https://example.com/ocpi/cpo/2.2.1"))
  let raw := jv.stringify(versions.detail_to_json(d))
  assert_true(
    str.contains(raw, "\"version\":\"2.2.1\"")
      and str.contains(raw, "\"identifier\":\"locations\"")
      and str.contains(raw, "\"identifier\":\"credentials\""),
    "detail JSON shape")
}

# ---- Standard CPO endpoint set ----------------------------------

fn test_standard_cpo_endpoints_count() -> Result[Unit, Str] {
  let eps := versions.standard_cpo_v221_endpoints("https://example.com/ocpi/cpo/2.2.1")
  if list.len(eps) == 7 { pass() }
  else { fail("standard CPO v2.2.1 should list 7 endpoints") }
}

fn test_standard_emsp_endpoints_count() -> Result[Unit, Str] {
  let eps := versions.standard_emsp_v221_endpoints("https://example.com/ocpi/emsp/2.2.1")
  if list.len(eps) == 7 { pass() }
  else { fail("standard eMSP v2.2.1 should list 7 endpoints") }
}

# ---- Suite + runner ---------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    test_version_constants(),
    test_endpoint_sender(),
    test_endpoint_receiver(),
    test_endpoint_to_json_shape(),
    test_detail_to_json(),
    test_standard_cpo_endpoints_count(),
    test_standard_emsp_endpoints_count(),
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
