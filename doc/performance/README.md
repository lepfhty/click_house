# Performance tickets

Candidate performance work for the driver, written for triage. One file per ticket.

Guiding rule: this is a library used in many environments, so **defaults must be
compatible first and fast second**. Anything that changes returned data, depends on a
server setting, adds a dependency, or shifts CPU/network trade-offs ships as opt-in
config; only changes with identical observable behavior may change defaults.

Numbers come from offline benchmarks (200k rows, Ruby 3.3, no ClickHouse server).
Network items are from code reading and still need measurement against a real server.

| # | Ticket | Area | Default-safe? | Impact | Effort |
|---|--------|------|---------------|--------|--------|
| 01 | [Avoid copying the response body to check emptiness](01-empty-body-check-copies-body.md) | memory | yes | low–med | XS |
| 02 | [Faster DateTime / DateTime64 casting](02-faster-datetime-casting.md) | cpu | yes | high for time-heavy reads | S |
| 03 | [Opt-in HTTP compression](03-opt-in-http-compression.md) | network | no → opt-in | high on remote links | S |
| 04 | [Opt-in persistent connections](04-opt-in-persistent-connections.md) | latency | no → opt-in + docs | high for many small queries | S–M |
| 05 | [Streaming select API](05-streaming-select.md) | memory | yes (additive) | high for large results | M |
| 06 | [Opt-in: skip BigDecimal for every JSON number](06-opt-in-skip-bigdecimal-parsing.md) | cpu/memory | no → opt-in | medium | S |
| 07 | [Make `send_progress_in_http_headers` configurable](07-investigate-send-progress-headers.md) | compat | yes (default stays on, opt-out added) | high for `readonly=1` and proxied users | S |
| 08 | [Resolve each column's casters once per result](08-compiled-column-casters.md) | cpu | yes | medium–high for wide or large reads | S |
| 09 | [Skip columns whose JSON values need no casting](09-skip-no-op-casts.md) | cpu | yes for server responses | medium for string-heavy reads | S |

Status values used in tickets: `proposed`, `accepted`, `in progress`, `done`, `rejected`.
