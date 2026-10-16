# 08 — Resolve each column's casters once per result

- **Status:** in progress
- **Area:** cpu
- **Default-safe:** yes, provided results are identical (verify)
- **Effort:** S

## Problem
`ResultSet#to_a` repeats the same type dispatch for every cell. For each value it calls
`types.fetch(name)`, then checks `container?`, `map?` and `tuple?` on the column's caster
and splats `argument_values` into `cast`. Nullable, LowCardinality and Array values also
go through `cast_container` and a block that runs `cast_type` again for the inner type. A
column's type is the same in every row, so this dispatch can be done once per result.

Ticket 02 made the casters themselves faster. This ticket is about the loop that calls them.

## Evidence (200k values, cast only, Ruby 3.3.5, json 2.6.2, bigdecimal 3.1.5)
Per column, current `to_a` vs a per-column lambda resolved once:

| Type | Now | Resolved once |
|---|---|---|
| `UInt64` | 0.058 s | 0.026 s |
| `String` | 0.061 s | 0.023 s |
| `LowCardinality(String)` | 0.082 s | 0.022 s |
| `Decimal(18, 4)` | 0.054 s | 0.030 s |
| `Date` | 0.107 s | 0.072 s |
| `Map(String, UInt64)` | 0.282 s | 0.170 s |
| `Float64` | 0.234 s | 0.197 s |
| `DateTime('UTC')` | 0.604 s | 0.510 s |

The gain is fixed per cell, so it's largest for cheap types. Float64 and DateTime gain
little because `Float(BigDecimal)` (see ticket 06) and `zone.local` dominate. In an
end-to-end prototype on 200k rows of the benchmark's mixed table against ClickHouse 26.3,
`select_all(...).to_a` went from 3.4 s to 2.1 s with no wire format change.

## Proposal
- Build one callable per column from its `Ast::Statement` tree, the first time `to_a`
  needs it, and memoize it alongside `types`.
- Resolve the caster's dispatch while building the callable: containers call
  `cast_each` with the inner column's callable, maps and tuples keep their
  `Hash(value)` / `Array(value)` coercion, and scalars call `cast(value, *argument_values)`.
- Keep the row loop as it is (iterate each row's own keys, assign in place, raise
  `KeyError` for a key that isn't in `meta`), so `to_a` returns the same objects as today.

## Compatibility checks before shipping
- Same values and classes for every type, including nested containers, `Map`, `Tuple`
  and `nil` in `Nullable`.
- Custom casters registered with `ClickHouse.add_type` go through the same methods
  (`container?`, `map?`, `tuple?`, `cast_each`, `cast`).
- An empty result still doesn't parse `meta`.
- `symbolize_keys` keeps working.

## Out of scope
- Building rows from arrays (JSONCompact): measured as a 0–3 point gain on top of this
  with json 3.x.
- Named tuples (`Tuple(a String, b UInt8)`) resolve to `UndefinedType` today. That's a
  separate bug.
