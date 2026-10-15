# 02 — Full-stack specs that don't need a server

- **Status:** proposed
- **Area:** tests
- **Effort:** S–M

## Problem
Almost every spec runs against a live ClickHouse, so every local run needs Docker and
every CI job needs a server. The offline specs that exist, such as
`spec/click_house/middleware/response_parsers_spec.rb`, call one middleware with a
hand-built `Faraday::Env`. Nothing in between runs the whole driver against a canned
response, through:

- the middleware stack in the order `Connection#transport` builds it (raising errors,
  logging, summary, JSON/CSV parsing);
- `Connection` itself (GET vs POST, query params, headers);
- `Response::Factory` and `ResultSet` type casting.

That gap makes some behavior hard to test:
- **Server behavior that's hard to trigger:** a query that fails after the server has
  sent `200 OK` (the `X-ClickHouse-Exception-Code` header with a partial body); a
  chunked response cut off mid-stream; error bodies in the formats different versions
  use. Ticket 07's investigation needed large queries and precise timing to reproduce
  these against a real server.
- **Version differences without running each version:** quoted vs. unquoted 64-bit
  integers (`output_format_json_quote_64bit_integers` changed default in 26.x), JSON
  vs. text error bodies (23.5+), compressed responses (26.1+ defaults
  `enable_http_compression=1`).
- **Fast checks for performance work:** tickets 01, 02 and 06 in `doc/performance/`
  change parsing and casting and need quick evidence that the output is unchanged.

## Proposal
- Use Faraday's built-in test adapter (`Faraday::Adapter::Test`, in Faraday 1 and 2)
  with a `Faraday::Adapter::Test::Stubs` instance.
- `Connection#transport` calls `conn.adapter config.adapter`, which passes only the
  adapter name, but the test adapter also needs the stubs. Options:
  - allow `config.adapter` to be an array of adapter arguments and call
    `conn.adapter(*Array(config.adapter))`. That's a small, additive public change that
    also helps users of adapters that take arguments;
  - or keep the library unchanged and have the spec helper stub `Connection#transport`
    to swap the adapter. That needs no library change, but it is more brittle.
- Add a `spec/support` helper, e.g. `stub_clickhouse(method, path_or_query, status:,
  headers:, body:)`, that returns a connection built with the test adapter.
- Tag these specs (e.g. `:offline`) so they can run without a server:
  `rspec --tag offline`. The live-server suite stays as it is.
- Start with specs for the cases above, including the two known gaps from ticket 07:
  a mid-stream error after a large result surfacing as `NetworkException`, and a small
  result that fails partway raising `DbException` with partial JSON as its message.

## Out of scope
- Replacing live-server specs. They remain the source of truth for real server behavior.
- Fixing the ticket 07 gaps themselves. These specs make the fixes testable.
