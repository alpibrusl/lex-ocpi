# lex-ocpi — OCPI 2.2.1 HubClientInfo module
#
# HubClientInfo is a configuration module that lets OCPI Hubs tell
# their connected parties which other parties are online. Sender side
# (the Hub) ships a `ClientInfo` list; receiver side (CPO / eMSP)
# consumes it to know which peers it can reach.
#
# Spec references:
#   OCPI 2.2.1 — Part III §15 (HubClientInfo module)
#
# Effects: none.

import "std.list" as list

import "lex-schema/json_value"  as jv
import "lex-schema/schema"      as s
import "lex-schema/error"       as e

import "../role" as role

# ---- ConnectionStatus enum --------------------------------------

fn cs_connected() -> Str { "CONNECTED" }
fn cs_offline()   -> Str { "OFFLINE" }
fn cs_planned()   -> Str { "PLANNED" }
fn cs_suspended() -> Str { "SUSPENDED" }

fn all_connection_status() -> List[Str] {
  [cs_connected(), cs_offline(), cs_planned(), cs_suspended()]
}

# ---- ClientInfo -------------------------------------------------

fn client_info_schema() -> s.ModelSchema {
  {
    title: "ClientInfo",
    description: "OCPI 2.2.1 — ClientInfo object",
    fields: [
      s.required_str("country_code", [StrNonEmpty, StrMaxLen(2)]),
      s.required_str("party_id",     [StrNonEmpty, StrMaxLen(3)]),
      s.required_str("role",         [StrOneOf(role.all_roles_v221())]),
      s.required_str("status",       [StrOneOf(all_connection_status())]),
      s.required_str("last_updated", [StrNonEmpty]),
    ],
  }
}

fn validate_client_info(j :: jv.Json) -> Result[jv.Json, List[e.Error]] {
  s.validate(client_info_schema(), j)
}
