# lex-ocpi — Hub role (issue #9)
#
# In OCPI 2.2.1+, a Hub is an intermediary that sits between CPOs
# and eMSPs and forwards messages. Instead of N×M direct peerings,
# everyone talks to the Hub and the Hub routes to the right
# downstream peer. The OCPI spec models this as:
#
#   * A routing table: `(country_code, party_id)` → peer base URL +
#     token. The Hub's address book.
#
#   * A forward path: incoming request carries `OCPI-to-*` headers
#     identifying the intended recipient. The Hub looks up that
#     party in the routing table and re-issues the request to that
#     peer's base URL.
#
#   * ClientInfo broadcast: when a peer comes online / goes offline,
#     the Hub PUTs `/clientinfo/{cc}/{pid}` to every OTHER connected
#     peer so everyone has a current view of the network.
#
#   * Loop prevention: the Hub MUST NOT forward back to the
#     originating party — that would create infinite forwarding
#     loops in a multi-hub mesh. Simplest correct rule: refuse to
#     forward when `OCPI-to-*` equals `OCPI-from-*` (already at the
#     destination from the Hub's point of view).
#
#   * Hub error codes (4xxx): the spec carves out 4001-4004 for
#     hub-specific failures —
#       4001 missing_or_invalid_parameters
#       4002 unknown_receiver
#       4003 timeout_on_forwarded_request
#       4004 connection_problem
#     `src/status.lex` already has the constants; this module just
#     wires them into the routing errors.
#
# Design choices:
#
#   * **Pure table + effectful forward.** The `RoutingTable` is a
#     pure `Map[Str, PushTarget]` keyed on `"cc|pid"`. CRUD ops
#     (`add_peer` / `remove_peer` / `lookup`) are pure folds. Only
#     `forward(...)` and `broadcast_clientinfo(...)` carry
#     `[net, time]` — they delegate to `client.send_with_retry` so
#     transient downstream failures inherit issue #8's retry policy.
#
#   * **No mutation through the network.** The hub *forwards*
#     arbitrary OCPI requests but doesn't reach into their bodies.
#     Forward = pass through method + path + body + headers
#     unchanged (rewriting only the destination URL and the
#     Authorization token to the per-peer credential). The
#     `OCPI-from-*` headers are preserved so the receiver still
#     knows the original sender.
#
#   * **Loop prevention is conservative.** We refuse the forward
#     when `to_party == from_party`. A more sophisticated rule
#     (e.g. track a forwarding chain via a custom header) is
#     possible but isn't in the spec; the simple rule is enough
#     to prevent the obvious infinite loop.
#
#   * **Broadcast is `list.map`, not parallel.** Same reasoning as
#     `push.push_fanout` — `std.flow.parallel_list` needs
#     empty-effect closures, ours carry `[net, time]`; the runtime
#     is sequential under the hood today (spec §11.2 reserves true
#     threading for a future scheduler).
#
# Spec references:
#   OCPI 2.2.1 — Part III §15 (HubClientInfo module)
#   OCPI 2.2.1 — Part I  §6   (Status codes 4001-4004)
#   OCPI 2.3.0 — Part I  §6   (same hub error catalogue)
#
# Effects:
#   * `RoutingTable` CRUD — pure
#   * `forward`           — `[net, time]`
#   * `broadcast_clientinfo` — `[net, time]`

import "std.list" as list
import "std.map"  as map
import "std.str"  as str

import "lex-schema/json_value" as jv

import "./client"  as client
import "./party"   as party
import "./headers" as h
import "./push"    as push

# ---- RoutingTable ----------------------------------------------
#
# Pure address book. Keyed on `"<country_code>|<party_id>"` since
# `Map`'s key must be `Str`. `PartyId` carries both fields; the
# `key_of` helper renders the tuple, used by every CRUD op.
#
# `PushTarget` (from `src/push.lex`) is reused — it already carries
# the per-peer `base_url` + `token` we need.

type RoutingTable = {
  peers :: Map[Str, push.PushTarget],
}

fn empty_table() -> RoutingTable {
  { peers: map.new() }
}

fn key_of(p :: party.PartyId) -> Str
  examples {
    key_of({ country_code: "NL", party_id: "EXM" }) => "NL|EXM",
  }
{
  str.concat(p.country_code, str.concat("|", p.party_id))
}

fn add_peer(t :: RoutingTable, target :: push.PushTarget) -> RoutingTable {
  { peers: map.set(t.peers, key_of(target.party), target) }
}

fn remove_peer(t :: RoutingTable, p :: party.PartyId) -> RoutingTable {
  { peers: map.delete(t.peers, key_of(p)) }
}

fn lookup(t :: RoutingTable, p :: party.PartyId) -> Option[push.PushTarget] {
  map.get(t.peers, key_of(p))
}

fn peer_count(t :: RoutingTable) -> Int {
  map.size(t.peers)
}

# All registered peer parties — used by `broadcast_clientinfo` to
# fan out and by the conformance harness to enumerate the address
# book.
fn all_parties(t :: RoutingTable) -> List[party.PartyId] {
  list.map(map.entries(t.peers),
    fn (kv :: (Str, push.PushTarget)) -> party.PartyId {
      match kv { (_, v) => v.party }
    })
}

# ---- RoutingError ----------------------------------------------

type RoutingError =
    UnknownReceiver(party.PartyId)            # `to_party` not in the table
  | LoopDetected({ from :: party.PartyId,     # hub refuses to forward
                   to   :: party.PartyId })   #   back to the sender
  | ForwardFailed(client.ClientError)         # downstream returned an error
                                                #   we already retried per policy

# Map a `RoutingError` onto the spec's 4xxx hub-status code so
# the hub can answer the original sender with a well-shaped OCPI
# envelope. `connection_problem` (4004) is the catch-all for
# transport-level failures; `unknown_receiver` (4002) for the
# missing-peer case; `missing_or_invalid_parameters` (4001) for
# the loop case (the spec doesn't carve out a dedicated code).
fn error_to_status_code(e :: RoutingError) -> Int {
  match e {
    UnknownReceiver(_) => 4002,
    LoopDetected(_)    => 4001,
    ForwardFailed(_)   => 4004,
  }
}

fn error_to_message(e :: RoutingError) -> Str {
  match e {
    UnknownReceiver(p) => str.concat("unknown receiver: ", key_of(p)),
    LoopDetected(d)    => str.concat("forward loop refused: from=",
                            str.concat(key_of(d.from),
                              str.concat(" to=", key_of(d.to)))),
    ForwardFailed(_)   => "downstream forward failed (see ClientError)",
  }
}

# ---- forward ---------------------------------------------------
#
# Generic OCPI forward. The hub doesn't need to know the typed
# shape of the forwarded payload — it copies method + path + body
# + party headers through, rewriting only the destination URL
# (peer base_url + module path) and the Authorization token (to
# the per-peer credential the hub holds for this downstream).
#
# `module_path` is the OCPI module-relative path the request
# targets, e.g. `/locations/NL/EXM/L1` for a CPO→eMSP location
# push. The hub strips its own mount prefix before calling
# `forward` — that's the caller's responsibility, since only the
# caller knows what its own mount point is.

fn forward(
  policy      :: client.RetryPolicy,
  table       :: RoutingTable,
  from_party  :: party.PartyId,
  to_party    :: party.PartyId,
  method      :: Str,
  module_path :: Str,
  body        :: Option[jv.Json]
) -> [net, time] Result[jv.Json, RoutingError] {
  # 1. Loop prevention: refuse if from == to. The hub never
  #    forwards a request back to the party that sent it (would
  #    cause the receiver to bounce it right back to us).
  if same_party(from_party, to_party) {
    Err(LoopDetected({ from: from_party, to: to_party }))
  } else {
    # 2. Routing lookup.
    match lookup(table, to_party) {
      None         => Err(UnknownReceiver(to_party)),
      Some(target) => execute_forward(policy, target, from_party, method,
                                       module_path, body),
    }
  }
}

fn same_party(a :: party.PartyId, b :: party.PartyId) -> Bool {
  a.country_code == b.country_code and a.party_id == b.party_id
}

fn execute_forward(
  policy      :: client.RetryPolicy,
  target      :: push.PushTarget,
  from_party  :: party.PartyId,
  method      :: Str,
  module_path :: Str,
  body        :: Option[jv.Json]
) -> [net, time] Result[jv.Json, RoutingError] {
  let req := build_forward_request(target, from_party, method, module_path, body)
  match client.send_with_retry(req, policy) {
    Ok(j)  => Ok(j),
    Err(e) => Err(ForwardFailed(e)),
  }
}

# Pure request builder — `forward`'s glue between the routing
# decision and `client.send_with_retry`. Exposed for the
# conformance harness so tests can assert on the request shape
# without a live socket.

fn build_forward_request(
  target      :: push.PushTarget,
  from_party  :: party.PartyId,
  method      :: Str,
  module_path :: Str,
  body        :: Option[jv.Json]
) -> HttpRequest {
  let url    := str.concat(target.base_url, module_path)
  let base   := client.base_request(method, url)
  let with_t := client.with_token(base, target.token)
  let with_r := client.with_party_routing(with_t, from_party, target.party)
  match body {
    None    => with_r,
    Some(j) => client.with_json_body(with_r, jv.stringify(j)),
  }
}

# ---- broadcast_clientinfo --------------------------------------
#
# When a peer's connection state changes (e.g. CONNECTED → OFFLINE)
# the hub notifies every OTHER connected peer via
# `PUT /clientinfo/{cc}/{pid}`. The hub does NOT notify the party
# whose state changed (they already know — they're the ones who
# went offline) and does NOT notify itself (it's not in the table
# anyway).
#
# Returns one (party, result) pair per recipient so callers can
# log which broadcasts succeeded and which failed.

fn broadcast_clientinfo(
  policy        :: client.RetryPolicy,
  table         :: RoutingTable,
  hub_party     :: party.PartyId,           # the hub's own from-party
  subject_party :: party.PartyId,           # whose state changed
  subject_uid   :: Str,                      # path: /clientinfo/{cc}/{pid}/{uid}
  client_info   :: jv.Json                  # the ClientInfo body
) -> [net, time] List[(party.PartyId, Result[jv.Json, RoutingError])] {
  let recipients := list.filter(all_parties(table),
    fn (p :: party.PartyId) -> Bool { same_party(p, subject_party) == false })
  list.map(recipients,
    fn (recipient :: party.PartyId) -> [net, time] (party.PartyId, Result[jv.Json, RoutingError]) {
      let path := clientinfo_path(subject_party, subject_uid)
      let r := forward(policy, table, hub_party, recipient, "PUT", path,
                       Some(client_info))
      (recipient, r)
    })
}

# `/clientinfo/{cc}/{pid}/{uid}` per the spec — the subject party
# is the *content* of the broadcast (whose state changed), not
# the recipient.
fn clientinfo_path(p :: party.PartyId, uid :: Str) -> Str
  examples {
    clientinfo_path({ country_code: "NL", party_id: "EXM" }, "u-1") =>
      "/clientinfo/NL/EXM/u-1",
  }
{
  str.concat("/clientinfo/",
    str.concat(p.country_code,
      str.concat("/",
        str.concat(p.party_id, str.concat("/", uid)))))
}
