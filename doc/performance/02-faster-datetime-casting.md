# 02 — Faster DateTime / DateTime64 casting

- **Status:** proposed
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

## Not proposed as default
`date_time_output_format=unix_timestamp` with `zone.at(int)` is about 9x faster, but it
is a server setting (rejected for `readonly=1` users) and changes raw `.data`. It could
be a later opt-in.
