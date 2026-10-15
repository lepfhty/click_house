# 02 — Full-stack specs that don't need a server

- **Status:** done
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

## Implementation
- `config.adapter` accepts an array of an adapter and its arguments;
  `Connection#transport` calls `conn.adapter(*Array(config.adapter))`. A symbol or class
  works as before. `Faraday::Adapter::Test` takes its stubs as the first argument on
  Faraday 1.10 and 2.7 alike.
- `spec/support/stub_clickhouse.rb`: `stub_clickhouse(status:, headers:, body:, **config)`
  returns a connection that answers every GET and POST with that response;
  `clickhouse_requests` records the method, path, params, headers and body sent.
- Examples tagged `:offline` skip the database setup hook in
  `spec/support/database_cleaner.rb`. The existing server-free unit specs are tagged too,
  so `rspec --tag offline` runs everything that doesn't need a server.
- Starter specs in `spec/click_house/offline/`: quoted and unquoted 64-bit integer
  casting, `symbolize_keys`, `X-ClickHouse-Summary`, the exception header with a 200
  status, a 404 with an `application/json` error body, and the params sent for GET and
  POST.

### Ticket 07 gaps
Captured from 22.9 and 26.3 with
`SELECT number, throwIf(number = 2, 'boom') FROM numbers(3) SETTINGS max_block_size=1`.
The outcome depends on whether the server had flushed the response headers when the
query failed.

- **Small result that fails partway** (headers not yet flushed): the server sends a 500
  with `X-ClickHouse-Exception-Code`, and the body is the partial JSON followed by the
  error text. The driver raises `DbException` with the whole body as its message.
  Reproducible; covered by a `pending` spec that expects only the error text.
- **Headers already flushed**: a 200 with no exception code header. 22.9 appends the
  error text to the partial JSON; 26.3 appends an `__exception__` block tagged with the
  `X-ClickHouse-Exception-Tag` header value. The driver raises `JSON::ParserError` or
  `Oj::ParseError` instead of `DbException`. Reproducible; the 26.x form, which the tag
  header makes detectable, is covered by a `pending` spec. The 22.9 form has no marker
  to detect it by, so it's only described here.
- **Large result that fails mid-stream** (`NetworkException: end of file reached`): not
  reproducible with the test adapter. The server aborts the chunked body and Net::HTTP
  raises `EOFError` while reading it, before any response middleware runs. A stub can
  only raise `Faraday::ConnectionFailed` itself, which tests `RaiseError`'s mapping, not
  the server behavior. Testing a fix needs a live server or a socket-level fake.
