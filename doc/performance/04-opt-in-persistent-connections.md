# 04 — Opt-in persistent connections

- **Status:** proposed
- **Area:** latency
- **Default-safe:** no → opt-in plus documentation
- **Effort:** S–M

## Problem
With the default adapter (`Faraday.default_adapter`, `net_http`), faraday-net_http calls
`Net::HTTP.new` + `start` for every request. Every query pays a TCP handshake, plus TLS on
https. The README's connection-pool example pools `ClickHouse::Connection` objects, but
each still opens a new socket for every request.

## Evidence
Code reading (faraday-net_http 3.0.2). Expected saving: 1 RTT per query, 2–3 with TLS.
Needs measurement against a remote/TLS server.

## Why not on by default
- Needs an extra gem (`faraday-net_http_persistent`); the driver shouldn't require it.
- Persistent sockets must not be shared across `fork` (Puma, Unicorn, Resque, Spring).
- Idle connections can be closed by the server's `keep_alive_timeout` or by proxies;
  automatic retry is only safe for idempotent requests. Inserts are POSTs and must not be
  retried silently.

## Proposal
- README section "Persistent connections": `config.adapter = :net_http_persistent`,
  with idle-timeout guidance (below the server's `keep_alive_timeout`) and fork-safety
  notes.
- Make sure `Connection#transport` works with that adapter on Faraday 1 and 2, and add a
  CI job that runs with it.
- Optional: a `Connection#reset!` / `close` that drops `@transport`, for after-fork hooks.
