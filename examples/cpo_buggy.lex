# lex-ocpi — deliberately-buggy CPO for harness self-test (issue #10)
#
# Counterpart to `examples/cpo_v221.lex`: serves the same URL
# surface but deliberately violates the OCPI envelope contract for
# every request. Used by `conformance/selftest.lex` to prove the
# harness's assertions actually catch bugs — if a case can pass
# against this server, the harness's teeth are missing.
#
# Wire shape:
#   * Status: HTTP 200 (so the client decodes the body and reaches
#     the envelope check).
#   * Body: `{"data": [], "status_code": 999, "timestamp": "…"}` —
#     status_code 999 is reserved nowhere in OCPI, so every
#     "is 1000" assertion fails, and the empty data list trips the
#     "data is non-empty" assertions too.
#
# Run:
#   lex run --allow-effects net,io,time examples/cpo_buggy.lex main

import "std.io"   as io
import "std.net"  as net
import "std.map"  as map
import "std.time" as time

import "lex-schema/json_value" as jv

import "../src/envelope" as env

fn handle(_req :: Request) -> [time] Response {
  let body := jv.stringify(JObj([
    ("data",        JList([])),
    ("status_code", JInt(999)),
    ("timestamp",   JStr(time.now_str())),
  ]))
  {
    body:    BodyStr(body),
    status:  200,
    headers: map.set(map.new(), "content-type", "application/json"),
  }
}

fn main() -> [net, io, time] Nil {
  let _ := io.print("buggy CPO  http://localhost:9103/ (always emits status_code 999)")
  net.serve_fn(9103, handle)
}
