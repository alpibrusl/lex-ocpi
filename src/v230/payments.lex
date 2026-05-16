# lex-ocpi — OCPI 2.3.0 Payments module
#
# Payments is **new in OCPI 2.3.0**. It standardises the wire shape
# for the eMSP (or Payment Terminal Provider — PTP) telling the CPO
# that a session has been paid for (or refunded, or disputed). Two
# core objects:
#
#   Payment      — a single payment event (eMSP/PTP → CPO push)
#   PaymentInfo  — context the CPO ships back in /payments/{id}
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "./enums" as en

# ---- Price (shared with v221 sessions / cdrs) -------------------

fn price_schema() -> s.ModelSchema {
  {
    title: "Price",
    description: "OCPI 2.3.0 — Price",
    fields: [
      s.required_float("excl_vat", []),
      s.optional(s.required_float("incl_vat", [])),
    ],
  }
}

# ---- PaymentMethod / PaymentReference --------------------------

fn payment_reference_schema() -> s.ModelSchema {
  {
    title: "PaymentReference",
    description: "OCPI 2.3.0 — opaque PSP / acquirer reference",
    fields: [
      s.required_str("issuer",    [StrNonEmpty, StrMaxLen(64)]),
      s.required_str("reference", [StrNonEmpty, StrMaxLen(255)]),
    ],
  }
}

# ---- Payment (the wire-shipped object) --------------------------

fn payment_schema() -> s.ModelSchema {
  {
    title: "Payment",
    description: "OCPI 2.3.0 — Payment object",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("id",           [StrNonEmpty, StrMaxLen(36)]),
      s.optional(s.required_str("session_id", [StrNonEmpty, StrMaxLen(36)])),
      s.optional(s.required_str("cdr_id",     [StrNonEmpty, StrMaxLen(36)])),
      s.required_str("method",       [StrOneOf(en.all_payment_method())]),
      s.required_str("status",       [StrOneOf(en.all_payment_status())]),
      s.required_str("currency",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_object("amount",    price_schema()),
      s.required_str("authorized_at", [StrNonEmpty]),
      s.optional(s.required_str("captured_at",  [StrNonEmpty])),
      s.optional(s.required_str("refunded_at",  [StrNonEmpty])),
      s.optional(s.required_object("psp_reference",
        payment_reference_schema())),
      s.optional(s.required_str("remark", [StrMaxLen(255)])),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_payment(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(payment_schema(), j)
}

# ---- PaymentInfo (CPO snapshot for downstream readers) ----------

fn payment_info_schema() -> s.ModelSchema {
  {
    title: "PaymentInfo",
    description: "OCPI 2.3.0 — PaymentInfo (read-only payment summary)",
    fields: [
      s.required_str("payment_id",   [StrNonEmpty, StrMaxLen(36)]),
      s.required_str("status",       [StrOneOf(en.all_payment_status())]),
      s.required_object("amount",    price_schema()),
      s.required_str("currency",     [StrNonEmpty, StrMaxLen(3)]),
      s.optional(s.required_str("note", [StrMaxLen(255)])),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_payment_info(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(payment_info_schema(), j)
}
