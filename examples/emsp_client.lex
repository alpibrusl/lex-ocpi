# lex-ocpi — eMSP-side client demo
#
# Walks the OCPI 2.2.1 discovery flow from the eMSP perspective:
#   1. GET /ocpi/versions          → pick a version we support
#   2. GET /ocpi/2.2.1/            → discover the CPO's endpoint set
#   3. GET /ocpi/2.2.1/locations/  → pull the first page of Locations
#
# Run against the bundled CPO example (`examples/cpo_v221.lex`):
#
#   # Terminal A — CPO
#   lex run --allow-effects net,io,time examples/cpo_v221.lex main
#
#   # Terminal B — eMSP
#   lex run --allow-effects net,io examples/emsp_client.lex main
#
# Effects: `[net, io]` — net for the HTTP calls, io for printing the
# decoded data. No persistence in the demo.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

import "../src/client" as client

# ---- Helpers ----------------------------------------------------
fn format_error(err :: client.ClientError) -> Str {
  match err {
    HttpFailed(m) => str.concat("transport: ", m),
    BadEnvelope(m) => str.concat("decode:    ", m),
    OcpiError(r) => str.concat("ocpi ", str.concat(int_to_str_safe(r.status_code), str.concat(" — ", r.status_message))),
  }
}

fn int_to_str_safe(n :: Int) -> Str {
  match n {
    1000 => "1000",
    2000 => "2000",
    2001 => "2001",
    2003 => "2003",
    2004 => "2004",
    3000 => "3000",
    _ => "????",
  }
}

# ---- Workflow ---------------------------------------------------
fn discover_versions(cpo_url :: Str, token :: Str) -> [net, io] Bool {
  let __lex_discard_1 := io.print(str.concat("→ GET ", cpo_url))
  match client.get_with_token(cpo_url, token) {
    Err(err) => {
      let __lex_discard_2 := io.print(str.concat("  ✗ ", format_error(err)))
      false
    },
    Ok(data) => {
      let __lex_discard_3 := io.print(str.concat("  ✓ versions: ", jv.stringify(data)))
      true
    },
  }
}

fn discover_endpoints(version_url :: Str, token :: Str) -> [net, io] Bool {
  let __lex_discard_4 := io.print(str.concat("→ GET ", version_url))
  match client.get_with_token(version_url, token) {
    Err(err) => {
      let __lex_discard_5 := io.print(str.concat("  ✗ ", format_error(err)))
      false
    },
    Ok(data) => {
      let __lex_discard_6 := io.print(str.concat("  ✓ endpoints: ", jv.stringify(data)))
      true
    },
  }
}

fn fetch_location(loc_url :: Str, token :: Str) -> [net, io] Bool {
  let __lex_discard_7 := io.print(str.concat("→ GET ", loc_url))
  match client.get_with_token(loc_url, token) {
    Err(err) => {
      let __lex_discard_8 := io.print(str.concat("  ✗ ", format_error(err)))
      false
    },
    Ok(data) => {
      let __lex_discard_9 := io.print(str.concat("  ✓ location: ", jv.stringify(data)))
      true
    },
  }
}

fn fetch_unknown_location(bogus_url :: Str, token :: Str) -> [net, io] Bool {
  let __lex_discard_10 := io.print(str.concat("→ GET ", bogus_url))
  match client.get_with_token(bogus_url, token) {
    Err(OcpiError(r)) => {
      let __lex_discard_11 := io.print(str.concat("  ✓ expected 2xxx envelope: ", str.concat(int_to_str_safe(r.status_code), str.concat(" — ", r.status_message))))
      true
    },
    Err(other) => {
      let __lex_discard_12 := io.print(str.concat("  ✗ unexpected error: ", format_error(other)))
      false
    },
    Ok(_) => {
      let __lex_discard_13 := io.print("  ✗ unexpected success — bogus LOC should 2xxx")
      false
    },
  }
}

# ---- Entry point ------------------------------------------------
fn main() -> [net, io] Nil {
  let __lex_discard_14 := io.print("eMSP client demo — talking to local CPO")
  let __lex_discard_15 := io.print("=========================================")
  let token := "demo-token"
  let __lex_discard_16 := discover_versions("http://localhost:9100/ocpi/versions", token)
  let __lex_discard_17 := discover_endpoints("http://localhost:9100/ocpi/2.2.1/", token)
  let __lex_discard_18 := fetch_location("http://localhost:9100/ocpi/2.2.1/locations/LOC1", token)
  let __lex_discard_19 := fetch_unknown_location("http://localhost:9100/ocpi/2.2.1/locations/LOC9", token)
  let __lex_discard_20 := io.print("=========================================")
  io.print("done")
}

