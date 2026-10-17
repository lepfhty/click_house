# Recommended client configuration

Why each setting in the README's [recommended configuration](../README.md#recommended)
is there, and what to change for other setups.

json 3 and Faraday 1.10.6+ on Ruby 3.3 both work. json 3.x parses roughly twice as fast
as 2.6, and bigdecimal 4.x converts `BigDecimal` to `Float` about 3x faster than 3.1.

## What each part does

- **`ssl_verify`** defaults to `false`, so over https the driver encrypts but accepts any
  certificate. Turn it on. A server with a private CA needs that CA in Ruby's trust store
  (e.g. `SSL_CERT_FILE`).
- **`global_params`** now reach `select_all`, `select_one` and `select_value` as well as
  `execute` and `insert` (#19). Per-query `query:` params to `Connection#get` override
  them. Anything placed there affects selects, including `session_id` and output-format
  settings.
- **`parse_floats`.** By default every fractional JSON number becomes a `BigDecimal`,
  and Float64 columns are then converted back to `Float`. `parse_floats` parses them as
  `Float` instead and sends `output_format_json_quote_decimals=1`, so Decimal columns
  arrive as strings and keep their precision. That makes parsing and casting Float64
  columns about 60% faster, a reporting-shaped table (dates, strings, counts, Float64
  metrics) about 40% faster, and a mixed table 7–12% faster. `ResultSet#to_a` returns the
  same values as the defaults, except in columns the driver doesn't cast (`Dynamic`,
  `Variant`, `JSON`) and named `Tuple`s, where Decimal values stay strings. Raw
  `ResultSet#data` changes: Float64 values are `Float` and Decimal values are strings. It works with both JSON parsers and leaves
  `json_load_options` and `oj_load_options` as configured.
- **Persistent connections** save a round trip per query (more with TLS). A connection
  opens its sockets on first use, so make the first query in each worker after `fork`
  (Puma, Unicorn, Resque) rather than sharing sockets opened before it.
- **`timeout`.** The driver sends `send_progress_in_http_headers=1`, so the server keeps a
  long query's socket busy and the read timeout rarely fires on a running query. Use
  `max_execution_time` to bound queries and keep `timeout` above it as a safety net.
- **`max_execution_time`** applies to `execute` and `insert` too, so it also stops
  migrations, `INSERT … SELECT` and backfills. Lift it per call for those:
  `execute(sql, params: { max_execution_time: 0 })`.

## Situational settings

- **ClickHouse before 26.1:** responses aren't compressed by default. Add
  `enable_http_compression: 1` to `global_params` for remote links. 26.1+ compresses on
  its own, and Faraday 2 decompresses transparently.
- **`readonly=1` users** can't change settings, and the server rejects any query that
  tries. Every setting the driver sends must either match the user's profile or be
  removed with `nil` in `global_params`: the driver's own
  `send_progress_in_http_headers=1`, `max_execution_time`, and the
  `output_format_json_quote_decimals=1` that `parse_floats` sends. Without that setting,
  leave `parse_floats` off, or Decimal columns lose precision. Params that aren't settings
  (`database`, `session_id`, `query_id`, `default_format`) are fine. `readonly=2` users
  can change settings and run the recommended configuration as is.
- **A proxy that rejects large headers** (nginx answering 502): add
  `send_progress_in_http_headers: nil` to `global_params`. Queries then send nothing until
  they finish, so raise `timeout` above the longest query.
