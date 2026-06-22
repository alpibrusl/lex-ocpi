# lex-ocpi — Commands async runtime (slice 2 of issue #4)
#
# Slice 1 (`src/commands.lex`) shipped the typed ADT + the sync side:
# CPO replies to a command POST with `CommandResponse` immediately and
# then is expected to deliver the eventual `CommandResult` to the
# eMSP's `response_url` later. This module is the runtime that makes
# the later part work.
#
# Two roles, one module:
#
#   * **eMSP side.** After `submit_command(...)` returns, the eMSP
#     waits for the CPO to POST the `CommandResult` to the eMSP's
#     own callback URL (the `response_url` it embedded in the body).
#     That callback URL is served by a route the eMSP exposes; when
#     it fires, the in-flight registry is told the result is in.
#     `wait_for_result(...)` polls the registry until the result
#     arrives or the deadline passes.
#
#   * **CPO side.** Once the underlying action completes (charger
#     responded, reservation cancelled, …), the CPO POSTs the typed
#     `CommandResult` to the eMSP's `response_url` via
#     `callback_result(...)`.
#
# Concurrency primitive: `std.conc` synchronous-mailbox actor — one
# `Map[Str, Option[CommandResult]]` actor holds the registry, keyed
# on a response-id the eMSP chose when assembling the original
# command body. The `Register / Complete / Lookup` message ADT
# disambiguates inbound calls; the reply is a parallel ADT covering
# every possible response so the actor's handler is total.
#
# Polling vs. signalling: `std.conc` mailboxes are synchronous —
# `ask`/`tell` run under a per-actor mutex on the caller's thread;
# there's no `wait` / `notify`. We poll with `time.sleep_ms` between
# attempts. `time.sleep_ms` is capped at 60_000ms in the runtime, so
# `poll_interval_ms` belongs in (0, 60_000]. The poll loop itself
# is bounded by the caller-supplied deadline.
#
# Effects on this module:
#   * `inflight_handler`       — pure (no effect)
#   * `new_inflight`           — `[concurrent]`
#   * `wait_for_result`        — `[concurrent, time]`
#   * `callback_result`        — `[net]`
#   * `parse_result_post`      — pure
#
# Spec references:
#   OCPI 2.2.1 — Part III §13.4 (CommandResult delivery)
#   OCPI 2.3.0 — Part III §13.4
#
# The slice-1 sync helpers and ADTs live in `src/commands.lex`.

import "std.conc" as conc

import "std.map" as map

import "std.str" as str

import "std.time" as time

import "lex-schema/json_value" as jv

import "./client" as client

import "./commands" as cmds

import "./route" as route

import "./error" as oe

# ---- Inflight registry — message + reply ADTs -------------------
#
# The actor's state is `Map[Str, Option[CommandResult]]` — keyed on
# the eMSP-chosen response_id. Entry semantics:
#
#   missing  : never registered (caller hasn't started this command yet)
#   Some(None) : registered, waiting for CPO callback
#   Some(Some(r)) : completed — CPO callback arrived with `r`
#
# Yes, the value type is `Option[CommandResult]` so the actor can tell
# "registered-but-pending" apart from "never heard of it". `map.get`
# already returns `Option[V]`; we use the outer Option for membership
# and the inner Option for completion.
type InflightMsg = Register(Str) | Complete((Str, cmds.CommandResult)) | Lookup(Str) | Forget(Str)

type InflightReply = AckRegistered | AckCompleted | AckForgotten | LookupPending | LookupReady(cmds.CommandResult) | LookupUnknown

fn inflight_handler(state :: Map[Str, Option[cmds.CommandResult]], msg :: InflightMsg) -> (Map[Str, Option[cmds.CommandResult]], InflightReply) {
  match msg {
    Register(id) => (map.set(state, id, None), AckRegistered),
    Complete(id, r) => (map.set(state, id, Some(r)), AckCompleted),
    Forget(id) => (map.delete(state, id), AckForgotten),
    Lookup(id) => (state, lookup_reply(state, id)),
  }
}

fn lookup_reply(state :: Map[Str, Option[cmds.CommandResult]], id :: Str) -> InflightReply {
  match map.get(state, id) {
    None => LookupUnknown,
    Some(slot) => match slot {
      None => LookupPending,
      Some(r) => LookupReady(r),
    },
  }
}

# Spawn a fresh inflight registry. One per eMSP process — the actor
# is what makes concurrent callback POSTs and in-flight reads safe.
fn new_inflight() -> [concurrent] Actor[Map[Str, Option[cmds.CommandResult]]] {
  conc.spawn(map.new(), inflight_handler)
}

# Thin wrappers so callers don't have to spell the message ADT at
# every call site. All three carry `[concurrent]`.
fn register(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], id :: Str) -> [concurrent] Unit {
  conc.tell(actor, Register(id))
}

fn complete(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], id :: Str, result :: cmds.CommandResult) -> [concurrent] Unit {
  conc.tell(actor, Complete(id, result))
}

fn forget(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], id :: Str) -> [concurrent] Unit {
  conc.tell(actor, Forget(id))
}

fn lookup(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], id :: Str) -> [concurrent] InflightReply {
  conc.ask(actor, Lookup(id))
}

# ---- Polling-with-timeout wait ---------------------------------
#
# Block until either the CPO's callback has filled in the result or
# the deadline passes. Returns `WaitUnknown` if the id was never
# registered (caller bug — likely forgot to `register` before
# `submit_command`). Returns `WaitTimeout` if the CPO didn't call
# back in time (this is the spec's `Failed`/`Timeout` outcome on the
# eMSP side — the caller decides whether to retry).
#
# Polling cadence: `poll_interval_ms` between lookups. The runtime
# caps `time.sleep_ms` at 60_000 so `poll_interval_ms > 60_000` is
# silently treated as 60_000.
#
# Why not push-based: `std.conc` has no `wait` / `notify`. The
# mailbox is synchronous and the handler runs on the caller's
# thread under a per-actor mutex. Push delivery is doable by
# spinning a goroutine-equivalent but goroutines aren't a Lex
# primitive — actor-as-future is the closest equivalent and that's
# what we do here: the registry actor IS the future store.
type WaitError = WaitTimeout | WaitUnknown

fn wait_for_result(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], response_id :: Str, timeout_ms :: Int, poll_interval_ms :: Int) -> [concurrent, time] Result[cmds.CommandResult, WaitError] {
  let deadline_ns := compute_deadline(timeout_ms)
  poll_loop(actor, response_id, deadline_ns, poll_interval_ms)
}

# Pure split so the deadline math is testable without [time].
fn compute_deadline_from(start_ns :: Int, timeout_ms :: Int) -> Int
  examples {
    compute_deadline_from(0, 1500) => 1500000000,
    compute_deadline_from(100000000, 0) => 100000000
  }
{
  start_ns + timeout_ms * 1000000
}

fn compute_deadline(timeout_ms :: Int) -> [time] Int {
  compute_deadline_from(time.mono_ns(), timeout_ms)
}

# Tail-recursive poll. Each iteration: ask for state, decide,
# optionally sleep, recur. Termination is guaranteed by the
# deadline check — every iteration either returns or advances
# `time.mono_ns()`.
fn poll_loop(actor :: Actor[Map[Str, Option[cmds.CommandResult]]], response_id :: Str, deadline_ns :: Int, poll_interval_ms :: Int) -> [concurrent, time] Result[cmds.CommandResult, WaitError] {
  match lookup(actor, response_id) {
    LookupReady(r) => Ok(r),
    LookupUnknown => Err(WaitUnknown),
    LookupPending => if time.mono_ns() >= deadline_ns {
      Err(WaitTimeout)
    } else {
      let __lex_discard_1 := time.sleep_ms(poll_interval_ms)
      poll_loop(actor, response_id, deadline_ns, poll_interval_ms)
    },
    AckRegistered => Err(WaitUnknown),
    AckCompleted => Err(WaitUnknown),
    AckForgotten => Err(WaitUnknown),
  }
}

# ---- CPO-side callback POST ------------------------------------
#
# Once the CPO's underlying action finishes, this puts the typed
# `CommandResult` back on the wire. `response_url` came in on the
# original command body and was retained by the CPO's handler;
# `token_b64` is the eMSP credentials token (the same one the
# eMSP authenticates with on its own endpoints — OCPI's
# bidirectional-token model).
#
# Returns the eMSP's OCPI envelope decoded into client's
# `ClientError` shape so the CPO can decide whether to retry. The
# spec doesn't define an envelope shape for the eMSP's reply on
# this callback beyond the standard status-code semantics —
# `client.post_json` handles both transport + envelope failures.
fn callback_result(response_url :: Str, result :: cmds.CommandResult, token_b64 :: Str) -> [net] Result[jv.Json, client.ClientError] {
  let body := jv.stringify(cmds.encode_command_result(result))
  client.post_json(response_url, body, token_b64)
}

# ---- eMSP-side webhook parser ----------------------------------
#
# The eMSP exposes a route the CPO POSTs the CommandResult to. That
# route's handler needs to:
#
#   1. extract the response_id from the URL (whatever scheme the
#      eMSP picked when assembling `response_url`)
#   2. decode the JSON body into a typed `CommandResult`
#   3. `tell` the inflight actor `Complete(id, result)`
#   4. reply HOk to the CPO
#
# Step 3 carries `[concurrent]`, but `route.Handler` is typed pure.
# So we split: this parser is pure and returns a `ResultPost` value
# the caller dispatches on at the transport layer, where wiring
# `conc.tell` is fine (it's not inside `route.dispatch`). The
# pattern matches slice 1's `command_handler` — the route layer
# does what it can, the user fills in the effect-carrying tail.
type ResultPost = PostCompleted({ response_id :: Str, result :: cmds.CommandResult }) | PostBadResponseId(Str) | PostBadBody(Str)

fn parse_result_post(req :: route.OcpiRequest, extract_response_id :: (route.OcpiRequest) -> Option[Str]) -> ResultPost {
  match extract_response_id(req) {
    None => PostBadResponseId("unable to extract response_id from callback request"),
    Some(id) => match cmds.decode_command_result(req.body) {
      Err(why) => PostBadBody(why),
      Ok(r) => PostCompleted({ response_id: id, result: r }),
    },
  }
}

# Convenience: turn a `ResultPost` into an OCPI handler result. The
# happy path is HOkEmpty (eMSPs typically don't return a body to
# the CPO on a successful callback); the two error paths surface
# the validator-style 2001 with a clear message.
fn result_post_handler_result(p :: ResultPost) -> route.HandlerResult {
  match p {
    PostCompleted(_) => HOkEmpty,
    PostBadResponseId(m) => HErr(oe.invalid_parameters(m)),
    PostBadBody(m) => HErr(oe.invalid_parameters(m)),
  }
}

