# 02 — Faster DateTime / DateTime64 casting

- **Status:** done
- **Area:** cpu
- **Default-safe:** yes, provided results are identical (verify)
- **Effort:** S

## Problem
Timestamp columns dominate `ResultSet#to_a`. `DateTimeType#cast` and
`DateTime64Type#cast` call `Time.strptime`, and for zoned columns
`Time.find_zone(tz).strptime`, on every value — a zone lookup plus ActiveSupport's slow
`strptime` each time.

## Evidence (200k values)
| Type | Now | Alternative |
|---|---|---|
| `UInt64` / `String` / `Float64` | 0.05–0.07 s | (baseline) |
| `DateTime` | 0.56 s | |
| `DateTime('UTC')` | 1.00 s | 0.43 s via `zone.local(y, m, d, h, mi, s)` from integer slices |
| `DateTime64(3, 'UTC')` | 1.34 s | similar |

## Proposal
- Resolve the `ActiveSupport::TimeZone` once per column (cache on the `Ast::Statement`
  or the caster), not per value.
- Parse the fixed `YYYY-MM-DD HH:MM:SS[.fff…]` layout by slicing integers and building
  the time with `Time.local` / `Time.utc` / `zone.local`, keeping fractional seconds as a
  `Rational` for DateTime64. Fall back to `strptime` if the string doesn't match the layout.
- Must work on Ruby 2.7 (`Time.new(string)` is 3.2+ only, so don't rely on it).

## Compatibility checks before shipping
- Same class (`Time` vs `ActiveSupport::TimeWithZone`), zone and value as today.
- DST edges: ambiguous and non-existent local times must resolve the same way as
  `zone.strptime`.
- Nanosecond precision for `DateTime64(9)`.
- `DateType` is already fast (0.15 s); out of scope.

## Implementation
`ClickHouse::Type::TimeParser` matches the exact `YYYY-MM-DD hh:mm:ss` /
`YYYY-MM-DD hh:mm:ss.f…` layout with a strict regexp (month 01–12, day 01–31, hour 00–23,
minute and second 00–59, ASCII only), slices the integers and calls the same constructor
with the same arguments that the strptime path ends in: `Time.local(y, m, d, h, mi, s, usec)`
with `usec = fraction * 1_000_000` (as `Time.strptime` does) or `zone.local(y, m, d, h, mi, s + fraction)`
(the `TimeWithZone.new(nil, zone, utc_wall_clock)` path that `TimeZone#strptime` uses, so
DST gaps and overlaps resolve the same way). Any other input (hour 24, leap second 60,
unpadded fields, trailing text, nil, non-strings) falls back to the original strptime
call, so results and errors stay identical. Zones are resolved once per tz name and
cached in a `Concurrent::Map`.

Specs compare both casters with `Time.strptime` / `TimeZone#strptime` over a sweep of
inputs, process time zones and column zones.

Local micro-benchmark (200k values, best of 3, Ruby 3.3.5, ActiveSupport 7.0.4, cast only):

| Type | Before | After |
|---|---|---|
| `DateTime` | 0.50 s | 0.38 s |
| `DateTime('UTC')` | 0.82 s | 0.39 s |
| `DateTime('Europe/Moscow')` | 1.00 s | 0.55 s |
| `DateTime64(3)` | 0.49 s | 0.39 s |
| `DateTime64(3, 'UTC')` | 1.17 s | 0.60 s |
| `DateTime64(9, 'UTC')` | 1.27 s | 0.69 s |

`benchmark/results.csv` rows (offline suite, 100k rows, 10 iterations, Ruby 3.3.5,
Faraday 2, `wall_min_ms`, JSON parser; Oj is similar):

| Scenario | Before | After |
|---|---|---|
| `cast DateTime` | 209.5 ms | 178.7 ms (1.17x) |
| `cast DateTime('UTC')` | 428.0 ms | 184.1 ms (2.32x) |
| `cast DateTime64(3, 'UTC')` | 622.9 ms | 294.0 ms (2.12x) |

Allocations drop for zoned columns (1.40M → 1.30M, 3.50M → 2.50M) but rise for plain
`DateTime` (600k → 900k): slicing allocates a few short strings per value that
`Time.strptime`'s C parser doesn't. Reading digits with `getbyte` would avoid them at some
cost to readability.

The unzoned columns are bounded by `Time.local` itself (about 0.21 s per 200k), which
has to apply the process time zone's rules.

## Not proposed as default
`date_time_output_format=unix_timestamp` with `zone.at(int)` is about 9x faster, but it
is a server setting (rejected for `readonly=1` users) and changes raw `.data`. It could
be a later opt-in.
