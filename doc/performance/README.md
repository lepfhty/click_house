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
| 05 | [Streaming select API](05-streaming-select.md) | memory | yes (additive) | high for large results | M |

Status values used in tickets: `proposed`, `accepted`, `in progress`, `done`, `rejected`.
