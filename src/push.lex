# lex-ocpi — Outbound CPO→eMSP push fanout (issue #5)
#
# When a CPO's local state changes — a Location is added, an EVSE
# switches from AVAILABLE to CHARGING, a Session starts/updates/ends,
# a CDR is finalised — the spec wants it to PATCH/PUT/POST the change
# to every registered eMSP that pulls from this CPO. `src/client.lex`
# is the raw transport; this module is the change-detection / fanout
# layer on top.
#
# Design choices:
#
#   * **Explicit `notify(...)` in the handler.** The issue weighed
#     two shapes: a repo-observer (implicit, fired by lex-orm on
#     save) vs. explicit `notify` calls inside the handler. The
#     explicit form wins for v1: handlers are a small bounded set
#     and the explicit call site is easier to read + test. The
#     implicit variant can land later as a typed wrapper around
#     this module.
#
#   * **Retry inherited from `client.send_with_retry`.** Issue #5
#     called the retry policy out as a separate concern (issue #8);
#     #8 landed first and shipped `RetryPolicy` + `is_retryable` +
#     `send_with_retry`. We just pass the policy through and the
#     existing classifier handles 503/429/5xx for free.
#
#   * **Fanout is `list.map`, not `flow.parallel_list`.** `std.flow`'s
#     `parallel_list` requires closures with *empty* effect rows;
#     ours carry `[net, time]`. `parallel_list` is also sequential
#     today (spec §11.2 reserves true threading for a future
#     scheduler) — there's no behaviour difference; `list.map` is
#     effect-polymorphic and accepts our effectful closure cleanly.
#
#   * **URL shape is OCPI 2.2.1 / 2.3.0.** Paths include the
#     `{country_code}/{party_id}` segment per the
#     multi-tenant routing model. v2.1.1's flatter shape is a
#     follow-up — most production traffic is on 2.2.1 / 2.3.0
#     anyway.
#
# Spec references:
#   OCPI 2.2.1 — Part III §8 (Locations: PUT / PATCH)
#                          §9 (Sessions: PUT / PATCH)
#                          §10 (CDRs: POST)
#                          §11 (Tokens: PUT eMSP→CPO direction)
#   OCPI 2.3.0 — same module structure
#
# Effects: `[net, time]` end-to-end (inherited from `send_with_retry`).

import "std.str"  as str
import "std.list" as list

import "lex-schema/json_value" as jv

import "./client" as client
import "./party"  as party

# ---- PushTarget --------------------------------------------------
#
# Who we're pushing to. `base_url` is the *module-base* URL — the
# part before `/locations/`, `/sessions/`, etc. (typically the
# version-detail base, e.g. `https://emsp.example/ocpi/2.2.1`).
# `token` is the token the eMSP issued to us (i.e. their inbound
# token, our outbound).

type PushTarget = {
  party    :: party.PartyId,         # whom we're pushing to
  base_url :: Str,                   # version-base, no trailing slash
  token    :: Str,                   # eMSP's inbound token (b64)
}

# ---- PushKind ---------------------------------------------------
#
# What changed, in spec-shaped buckets. The per-variant record
# carries everything the URL builder and body encoder need; the
# `body` field is always a `jv.Json` so the caller decides whether
# to send a full-object PUT or a partial-object PATCH.
#
# Path conventions (OCPI 2.2.1 / 2.3.0):
#
#   LocationPut     PUT    {base}/locations/{cc}/{pid}/{location_id}
#   LocationPatch   PATCH  {base}/locations/{cc}/{pid}/{location_id}
#   EvsePatch       PATCH  {base}/locations/{cc}/{pid}/{location_id}/{evse_uid}
#   ConnectorPatch  PATCH  {base}/locations/{cc}/{pid}/{location_id}/{evse_uid}/{connector_id}
#   SessionPut      PUT    {base}/sessions/{cc}/{pid}/{session_id}
#   SessionPatch    PATCH  {base}/sessions/{cc}/{pid}/{session_id}
#   CdrPost         POST   {base}/cdrs
#   TokenPut        PUT    {base}/tokens/{cc}/{pid}/{token_uid}
#
# CdrPost has no party-tuple in the path: the receiver applies the
# `OCPI-from-*` headers for tenant routing (the CDR is a new object,
# the eMSP picks its own id on receipt).

type PushKind =
    LocationPut({
      country_code :: Str,
      party_id     :: Str,
      location_id  :: Str,
      body         :: jv.Json,
    })
  | LocationPatch({
      country_code :: Str,
      party_id     :: Str,
      location_id  :: Str,
      body         :: jv.Json,
    })
  | EvsePatch({
      country_code :: Str,
      party_id     :: Str,
      location_id  :: Str,
      evse_uid     :: Str,
      body         :: jv.Json,
    })
  | ConnectorPatch({
      country_code :: Str,
      party_id     :: Str,
      location_id  :: Str,
      evse_uid     :: Str,
      connector_id :: Str,
      body         :: jv.Json,
    })
  | SessionPut({
      country_code :: Str,
      party_id     :: Str,
      session_id   :: Str,
      body         :: jv.Json,
    })
  | SessionPatch({
      country_code :: Str,
      party_id     :: Str,
      session_id   :: Str,
      body         :: jv.Json,
    })
  | CdrPost({
      body :: jv.Json,
    })
  | TokenPut({
      country_code :: Str,
      party_id     :: Str,
      token_uid    :: Str,
      body         :: jv.Json,
    })

# ---- Pure helpers: per-kind URL / method / body -----------------

fn push_method(kind :: PushKind) -> Str
  examples {
    push_method(CdrPost({ body: JNull })) => "POST",
  }
{
  match kind {
    LocationPut(_)    => "PUT",
    LocationPatch(_)  => "PATCH",
    EvsePatch(_)      => "PATCH",
    ConnectorPatch(_) => "PATCH",
    SessionPut(_)     => "PUT",
    SessionPatch(_)   => "PATCH",
    CdrPost(_)        => "POST",
    TokenPut(_)       => "PUT",
  }
}

fn push_body(kind :: PushKind) -> jv.Json {
  match kind {
    LocationPut(p)    => p.body,
    LocationPatch(p)  => p.body,
    EvsePatch(p)      => p.body,
    ConnectorPatch(p) => p.body,
    SessionPut(p)     => p.body,
    SessionPatch(p)   => p.body,
    CdrPost(p)        => p.body,
    TokenPut(p)       => p.body,
  }
}

fn push_url(base_url :: Str, kind :: PushKind) -> Str {
  match kind {
    LocationPut(p)    => location_url(base_url, p.country_code, p.party_id, p.location_id),
    LocationPatch(p)  => location_url(base_url, p.country_code, p.party_id, p.location_id),
    EvsePatch(p)      => evse_url(base_url, p.country_code, p.party_id,
                                  p.location_id, p.evse_uid),
    ConnectorPatch(p) => connector_url(base_url, p.country_code, p.party_id,
                                       p.location_id, p.evse_uid, p.connector_id),
    SessionPut(p)     => session_url(base_url, p.country_code, p.party_id, p.session_id),
    SessionPatch(p)   => session_url(base_url, p.country_code, p.party_id, p.session_id),
    CdrPost(_)        => join4(base_url, "/cdrs", "", ""),
    TokenPut(p)       => token_url(base_url, p.country_code, p.party_id, p.token_uid),
  }
}

# URL-builder helpers. Spelled out per-shape rather than via a
# variadic `join` so each call site is concrete and re-orderings
# are loud.

fn location_url(base :: Str, cc :: Str, pid :: Str, loc :: Str) -> Str
  examples {
    location_url("https://emsp.example/ocpi/2.2.1", "NL", "TNM", "L1") =>
      "https://emsp.example/ocpi/2.2.1/locations/NL/TNM/L1",
  }
{
  join4(base, "/locations/", cc, str.concat("/", str.concat(pid, str.concat("/", loc))))
}

fn evse_url(
  base :: Str, cc :: Str, pid :: Str, loc :: Str, evse :: Str
) -> Str {
  str.concat(location_url(base, cc, pid, loc), str.concat("/", evse))
}

fn connector_url(
  base :: Str, cc :: Str, pid :: Str, loc :: Str, evse :: Str, conn :: Str
) -> Str {
  str.concat(evse_url(base, cc, pid, loc, evse), str.concat("/", conn))
}

fn session_url(base :: Str, cc :: Str, pid :: Str, sess :: Str) -> Str
  examples {
    session_url("https://emsp.example/ocpi/2.3.0", "DE", "ABC", "S-7") =>
      "https://emsp.example/ocpi/2.3.0/sessions/DE/ABC/S-7",
  }
{
  join4(base, "/sessions/", cc, str.concat("/", str.concat(pid, str.concat("/", sess))))
}

fn token_url(base :: Str, cc :: Str, pid :: Str, uid :: Str) -> Str {
  join4(base, "/tokens/", cc, str.concat("/", str.concat(pid, str.concat("/", uid))))
}

fn join4(a :: Str, b :: Str, c :: Str, d :: Str) -> Str {
  str.concat(a, str.concat(b, str.concat(c, d)))
}

# ---- Single-target push -----------------------------------------
#
# Build the request from the `PushKind`, layer in OCPI headers
# (token + party routing — see `client.with_party_routing`), POST
# / PUT / PATCH it via `send_with_retry` so transient failures
# retry per `RetryPolicy`. The caller supplies a `from_party`
# because that's a CPO-side identity, not a property of the
# `PushTarget`.

fn push(
  policy     :: client.RetryPolicy,
  from_party :: party.PartyId,
  target     :: PushTarget,
  kind       :: PushKind
) -> [net, time] Result[jv.Json, client.ClientError] {
  let req := build_request(from_party, target, kind)
  client.send_with_retry(req, policy)
}

fn build_request(
  from_party :: party.PartyId,
  target     :: PushTarget,
  kind       :: PushKind
) -> HttpRequest {
  let url    := push_url(target.base_url, kind)
  let method := push_method(kind)
  let body   := jv.stringify(push_body(kind))
  let base   := client.base_request(method, url)
  let with_t := client.with_token(base, target.token)
  let with_r := client.with_party_routing(with_t, from_party, target.party)
  client.with_json_body(with_r, body)
}

# ---- N-target fanout --------------------------------------------
#
# `list.map` over the targets — each target gets its own retry loop
# and its own Result. Returns one Result per target in the input
# order so the caller can pair them up. A single target failing
# does NOT short-circuit the others.
#
# `list.map`'s effect row is open, so the closure's `[net, time]`
# propagates to the fanout's effect set automatically.

fn push_fanout(
  policy     :: client.RetryPolicy,
  from_party :: party.PartyId,
  targets    :: List[PushTarget],
  kind       :: PushKind
) -> [net, time] List[Result[jv.Json, client.ClientError]] {
  list.map(targets,
    fn (t :: PushTarget) -> [net, time] Result[jv.Json, client.ClientError] {
      push(policy, from_party, t, kind)
    })
}
