# lex-ocpi — OCPI spec-conformance assertions (issue #10)
#
# A library of pure predicates that walk an `OcpiResponse` / an
# `OcpiHeaders` value / a response-header map and verify it matches
# the wire-shape the OCPI spec requires. Every assertion returns
# `Result[Unit, ConformanceError]` so failures carry structured
# detail (which field, why) rather than a boolean.
#
# Two audiences:
#
#   1. **Tests**: replace ad-hoc `assert resp.status_code == 1000`
#      checks with `conformance.check_envelope(resp)` — gets the
#      whole spec invariant in one line.
#
#   2. **Production middleware**: a transport adapter can run
#      `check_envelope` on every outbound response as a safety net.
#      The cost is one record walk; the value is catching shape
#      regressions before they reach a peer.
#
# This module is the FOUNDATION layer of the conformance harness
# from issue #10. The matching live-loop scenarios (a fake HTTP
# peer that 503s twice, a 3-eMSP fanout with one failure, the
# multi-thread idempotency race) need a mock transport that
# doesn't exist yet — those slot in on top of this library in a
# future PR. What ships here is everything that's checkable
# against the **pure** wire-shape of the envelope + header
# contract — which is most of what OCPI conformance actually
# means.
#
# Spec references:
#   OCPI 2.2.1 — Part I §4   (Request / Response Objects)
#                       §6   (Status codes)
#                       §10  (HTTP transport — headers + pagination)
#   OCPI 2.3.0 — Part I §4   (same envelope shape)
#
# Effects: none.

import "std.str" as str

import "std.int" as int

import "std.map" as map

import "lex-schema/json_value" as jv

import "./envelope" as env

import "./headers" as h

import "./party" as party

import "./status" as status

# ---- ConformanceError ------------------------------------------
#
# Structured failure detail. Each variant is constructable from a
# single primitive so callers can pattern-match on the shape; the
# `render(e)` helper turns it into a Str for log lines / test
# failure messages.
type ConformanceError = EnvelopeFieldEmpty(Str) | StatusCodeOutOfBand(Int) | StatusMessageMissing(Int) | StatusMessageOnSuccess | HeaderMissing(Str) | HeaderMalformed({ name :: Str, why :: Str }) | HeaderEchoMismatch({ name :: Str, sent :: Str, received :: Str }) | PaginationFieldMissing(Str) | PaginationFieldInvalid({ name :: Str, value :: Str, why :: Str }) | DataShape(Str)

fn render(e :: ConformanceError) -> Str {
  match e {
    EnvelopeFieldEmpty(f) => str.concat("envelope field empty: ", f),
    StatusCodeOutOfBand(c) => str.concat("status_code out of band (1xxx-4xxx): ", int.to_str(c)),
    StatusMessageMissing(c) => str.concat("status_message empty for non-success code ", int.to_str(c)),
    StatusMessageOnSuccess => "status_message non-empty for 1xxx success",
    HeaderMissing(name) => str.concat("header missing: ", name),
    HeaderMalformed(d) => str.concat(str.concat("header ", d.name), str.concat(" malformed: ", d.why)),
    HeaderEchoMismatch(d) => str.concat(str.concat("header ", d.name), str.concat(" not echoed: sent=", str.concat(d.sent, str.concat(" received=", d.received)))),
    PaginationFieldMissing(n) => str.concat("pagination header missing: ", n),
    PaginationFieldInvalid(d) => str.concat(str.concat("pagination ", d.name), str.concat(" invalid (", str.concat(d.value, str.concat("): ", d.why)))),
    DataShape(why) => str.concat("data shape: ", why),
  }
}

# ---- Status-code classification --------------------------------
type StatusBand = Success | ClientError | ServerError | HubError | Unknown

fn classify(code :: Int) -> StatusBand
  examples {
    classify(1000) => Success,
    classify(2003) => ClientError,
    classify(3002) => ServerError,
    classify(4001) => HubError,
    classify(500) => Unknown,
    classify(0) => Unknown,
    classify(5000) => Unknown
  }
{
  if code >= 1000 and code < 2000 {
    Success
  } else {
    if code >= 2000 and code < 3000 {
      ClientError
    } else {
      if code >= 3000 and code < 4000 {
        ServerError
      } else {
        if code >= 4000 and code < 5000 {
          HubError
        } else {
          Unknown
        }
      }
    }
  }
}

# ---- Envelope shape --------------------------------------------
#
# Every OcpiResponse on the wire MUST have:
#   - status_code in 1000-4999 (one of the four OCPI bands)
#   - timestamp non-empty (ISO-8601; we don't parse, just check
#     presence — full date parsing is heavy and the validator
#     module covers it on inbound)
#   - status_message non-empty when status_code >= 2000 (the spec
#     phrases it as MUST for non-success; we treat empty as a
#     spec violation)
#
# `check_envelope(r)` returns the FIRST failing assertion. The
# all-errors variant is `check_envelope_all(r) -> List[ConformanceError]`.
fn check_envelope(r :: env.OcpiResponse) -> Result[Unit, ConformanceError]
  examples {
    check_envelope({ data: JNull, status_code: 1000, status_message: "", timestamp: "2026-05-16T00:00:00Z" }) => Ok(()),
    check_envelope({ data: JNull, status_code: 1000, status_message: "", timestamp: "" }) => Err(EnvelopeFieldEmpty("timestamp")),
    check_envelope({ data: JNull, status_code: 9999, status_message: "", timestamp: "2026-05-16T00:00:00Z" }) => Err(StatusCodeOutOfBand(9999)),
    check_envelope({ data: JNull, status_code: 2003, status_message: "", timestamp: "2026-05-16T00:00:00Z" }) => Err(StatusMessageMissing(2003))
  }
{
  match classify(r.status_code) {
    Unknown => Err(StatusCodeOutOfBand(r.status_code)),
    _ => if r.timestamp == "" {
      Err(EnvelopeFieldEmpty("timestamp"))
    } else {
      check_message_for_code(r.status_code, r.status_message)
    },
  }
}

fn check_message_for_code(code :: Int, message :: Str) -> Result[Unit, ConformanceError] {
  match classify(code) {
    Success => Ok(()),
    _ => if message == "" {
      Err(StatusMessageMissing(code))
    } else {
      Ok(())
    },
  }
}

# All-errors variant. Collects every violation in one pass.
fn check_envelope_all(r :: env.OcpiResponse) -> List[ConformanceError] {
  let band_err :: List[ConformanceError] := match classify(r.status_code) {
    Unknown => [StatusCodeOutOfBand(r.status_code)],
    _ => [],
  }
  let ts_err :: List[ConformanceError] := if r.timestamp == "" {
    [EnvelopeFieldEmpty("timestamp")]
  } else {
    []
  }
  let msg_err :: List[ConformanceError] := match check_message_for_code(r.status_code, r.status_message) {
    Ok(_) => [],
    Err(e) => [e],
  }
  list.concat(list.concat(band_err, ts_err), msg_err)
}

# ---- OCPI request headers -------------------------------------
#
# The eight functional-OCPI headers are not all mandatory on every
# request, but the four "transport" headers (Authorization,
# X-Request-ID, OCPI-from-*, OCPI-to-*) MUST be present on every
# inbound request that hits a module endpoint. The configuration
# layer (/credentials, /versions) doesn't require the party
# tuples; `check_module_request_headers` enforces the strict set,
# `check_config_request_headers` the lighter one.
fn check_module_request_headers(req :: h.OcpiHeaders) -> Result[Unit, ConformanceError]
  examples {
    check_module_request_headers(h.new("Token x", "rid-1", "corr-1", party.new("NL", "EXM"), party.new("DE", "ABC"))) => Ok(()),
    check_module_request_headers(h.new("", "rid", "corr", party.new("NL", "EXM"), party.new("DE", "ABC"))) => Err(HeaderMissing("authorization")),
    check_module_request_headers(h.new("Bearer x", "rid", "corr", party.new("NL", "EXM"), party.new("DE", "ABC"))) => Err(HeaderMalformed({ name: "authorization", why: "must start with 'Token '" }))
  }
{
  match check_authorization(req.authorization) {
    Err(e) => Err(e),
    Ok(_) => match check_non_empty(req.request_id, h.h_request_id()) {
      Err(e) => Err(e),
      Ok(_) => match check_party(req.from_party, "from") {
        Err(e) => Err(e),
        Ok(_) => check_party(req.to_party, "to"),
      },
    },
  }
}

fn check_config_request_headers(req :: h.OcpiHeaders) -> Result[Unit, ConformanceError] {
  match check_authorization(req.authorization) {
    Err(e) => Err(e),
    Ok(_) => check_non_empty(req.request_id, h.h_request_id()),
  }
}

# OCPI Authorization is `Token <base64>` — the scheme is fixed.
# Anything else (Bearer / Basic / missing) is a spec violation.
fn check_authorization(auth :: Str) -> Result[Unit, ConformanceError] {
  if auth == "" {
    Err(HeaderMissing(h.h_authorization()))
  } else {
    if str.starts_with(auth, "Token ") {
      Ok(())
    } else {
      Err(HeaderMalformed({ name: h.h_authorization(), why: "must start with 'Token '" }))
    }
  }
}

fn check_non_empty(s :: Str, name :: Str) -> Result[Unit, ConformanceError] {
  if s == "" {
    Err(HeaderMissing(name))
  } else {
    Ok(())
  }
}

# Party tuple validation: country_code = 2 chars, party_id = 3
# chars per spec. Empty values fail; mismatched lengths fail.
fn check_party(p :: party.PartyId, side :: Str) -> Result[Unit, ConformanceError] {
  let cc_name := if side == "from" {
    h.h_from_country_code()
  } else {
    h.h_to_country_code()
  }
  let pi_name := if side == "from" {
    h.h_from_party_id()
  } else {
    h.h_to_party_id()
  }
  if p.country_code == "" {
    Err(HeaderMissing(cc_name))
  } else {
    if str.len(p.country_code) != 2 {
      Err(HeaderMalformed({ name: cc_name, why: "country_code must be 2 chars (ISO-3166)" }))
    } else {
      if p.party_id == "" {
        Err(HeaderMissing(pi_name))
      } else {
        if str.len(p.party_id) != 3 {
          Err(HeaderMalformed({ name: pi_name, why: "party_id must be 3 chars" }))
        } else {
          Ok(())
        }
      }
    }
  }
}

# ---- Request → response header echo --------------------------
#
# Per spec, the response MUST echo X-Request-ID and X-Correlation-ID
# from the request. The party tuples ARE permitted to differ
# (server may swap from↔to), so we only require that they remain
# valid (non-empty + length-shaped).
fn check_response_echoes_request(req :: h.OcpiHeaders, resp_headers :: Map[Str, Str]) -> Result[Unit, ConformanceError] {
  match check_echo(req.request_id, resp_headers, h.h_request_id()) {
    Err(e) => Err(e),
    Ok(_) => check_echo(req.correlation_id, resp_headers, h.h_correlation_id()),
  }
}

fn check_echo(sent :: Str, resp_headers :: Map[Str, Str], name :: Str) -> Result[Unit, ConformanceError] {
  match map.get(resp_headers, name) {
    None => Err(HeaderMissing(name)),
    Some(got) => if got == sent {
      Ok(())
    } else {
      Err(HeaderEchoMismatch({ name: name, sent: sent, received: got }))
    },
  }
}

# ---- Pagination headers ---------------------------------------
#
# OCPI pagination is signalled by THREE response headers:
#   X-Total-Count: <int>        — total objects across all pages
#   X-Limit:       <int>        — page size used
#   Link:          <see RFC 5988> — present iff a next page exists
#
# `check_pagination_headers` enforces the X-* pair (always
# required on paginated endpoints) and validates them as
# non-negative integers; the Link header is checked separately
# because it's conditional.
fn check_pagination_headers(resp_headers :: Map[Str, Str]) -> Result[Unit, ConformanceError] {
  match check_int_header(resp_headers, "x-total-count") {
    Err(e) => Err(e),
    Ok(_) => check_int_header(resp_headers, "x-limit"),
  }
}

fn check_int_header(resp_headers :: Map[Str, Str], name :: Str) -> Result[Unit, ConformanceError] {
  match map.get(resp_headers, name) {
    None => Err(PaginationFieldMissing(name)),
    Some(s) => match str.to_int(s) {
      None => Err(PaginationFieldInvalid({ name: name, value: s, why: "not an integer" })),
      Some(n) => if n < 0 {
        Err(PaginationFieldInvalid({ name: name, value: s, why: "must be non-negative" }))
      } else {
        Ok(())
      },
    },
  }
}

# Link header is present iff there are more pages. We don't parse
# the RFC-5988 grammar; we just check it's non-empty and contains
# a rel="next" marker (the common case).
fn check_link_header_present(resp_headers :: Map[Str, Str]) -> Result[Unit, ConformanceError] {
  match map.get(resp_headers, "link") {
    None => Err(PaginationFieldMissing("link")),
    Some(s) => if s == "" {
      Err(PaginationFieldInvalid({ name: "link", value: "", why: "empty" }))
    } else {
      if str.contains(s, "rel=\"next\"") {
        Ok(())
      } else {
        Err(PaginationFieldInvalid({ name: "link", value: s, why: "missing rel=\"next\"" }))
      }
    },
  }
}

# ---- Convenience: assert + describe ---------------------------
#
# Pattern: in a test, you want one of:
#
#   * "give me Result[Unit, Str] so my test harness sees the
#     error in plain text" — `assert_envelope(r)`.
#   * "give me a Result with structured detail so I can switch on
#     it" — `check_envelope(r)`.
#
# `assert_*` wraps `check_*` with `render`.
fn assert_envelope(r :: env.OcpiResponse) -> Result[Unit, Str] {
  match check_envelope(r) {
    Ok(_) => Ok(()),
    Err(e) => Err(render(e)),
  }
}

fn assert_module_request_headers(req :: h.OcpiHeaders) -> Result[Unit, Str] {
  match check_module_request_headers(req) {
    Ok(_) => Ok(()),
    Err(e) => Err(render(e)),
  }
}

fn assert_response_echoes_request(req :: h.OcpiHeaders, resp_headers :: Map[Str, Str]) -> Result[Unit, Str] {
  match check_response_echoes_request(req, resp_headers) {
    Ok(_) => Ok(()),
    Err(e) => Err(render(e)),
  }
}

fn assert_pagination_headers(resp_headers :: Map[Str, Str]) -> Result[Unit, Str] {
  match check_pagination_headers(resp_headers) {
    Ok(_) => Ok(()),
    Err(e) => Err(render(e)),
  }
}

