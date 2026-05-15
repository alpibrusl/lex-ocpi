# lex-ocpi — interface role (Sender / Receiver)
#
# Every OCPI module endpoint advertises which **interface role** it
# implements: the Sender side pushes data, the Receiver side accepts
# it. A module typically has both endpoints (the Sender's endpoint
# is a `GET` / pull location; the Receiver's is a `PUT` / `PATCH`
# / `POST` push location).
#
# Spec references:
#   OCPI 2.2.1 — Part I §6 (Module list, "Interface")
#   OCPI 2.3.0 — Part I §6
#
# The wire spelling is `"SENDER"` / `"RECEIVER"` (uppercase). Pair
# with `module_id.*` to build `Endpoint` entries for the version
# detail response.
#
# Effects: none.

import "std.list" as list

fn sender()   -> Str { "SENDER" }
fn receiver() -> Str { "RECEIVER" }

fn all_interface_roles() -> List[Str] {
  [sender(), receiver()]
}
