# 09 — Skip columns whose JSON values need no casting

- **Status:** in progress
- **Area:** cpu
- **Default-safe:** yes for ClickHouse responses; hand-built `ResultSet`s change (see below)
- **Effort:** S
- **Depends on:** [08](08-compiled-column-casters.md)

## Problem
For many columns, ClickHouse's JSON already holds the value `to_a` returns, so their
casts change nothing. For example, String, UUID and Enum come back as the same strings,
and Nullable, LowCardinality and Array of those return their input. After ticket 08,
`to_a` still visits every cell of those columns and calls a caster that returns its
argument.

## Evidence
On ClickHouse 26.3, 7 of 10 columns in the benchmark's mixed table and 9 of 14 in a
reporting-shaped table come back from casting unchanged. Those columns take 41–50% of
cast time on master, and 36–41% after ticket 08. Some of them are no-ops only on some
servers: 22.9 quotes UInt64 and Int64, and Decimal is a no-op only while `json_load_options`
parses it into `BigDecimal`. So only types whose JSON form doesn't depend on the server
or config can be skipped up front.

A prototype on 200k rows (GC off, run-to-run noise about ±10%):

| | mixed | report |
|---|---|---|
| ticket 08 | -21% to -29% vs master | -22% |
| skip no-op columns | -39% to -43% | -39% |

## Proposal
- When building a column's caster, return nil if its built-in casters return their
  input: `StringType` (String, FixedString, UUID) and `UndefinedType` (types without a
  caster, e.g. Enum), alone or inside `Nullable`, `LowCardinality` and `Array`.
- Match those casters with `instance_of?`, so casters registered with `add_type`, and
  subclasses of the built-in ones, are never skipped.
- Loop over only the columns with a caster, instead of each row's keys.
- Skip a container only when it has an inner type, so a malformed type still raises once
  a value reaches it.
- Leave `Map` and `Tuple` out: they coerce `nil` to `{}` and `[]`, which skipping would
  change.

## Behavior changes
Only results built by hand can see these. Rows from a JSON response always have exactly
the `meta` columns. A query ending in `FORMAT JSONCompact*` sends array rows, which raise
`TypeError` (or come back uncast when no column needs casting) on master, after ticket 08
and after this ticket alike:
- A row key that isn't in `meta` is left unchanged instead of raising `KeyError`.
- A row that lacks a column gets that column's cast of `nil`, e.g. `TypeError` for an
  integer column. Previously the column was simply left absent.

## Not proposed
An `Integer` fast path (return the value when it's already an `Integer`) saved about
6 ms per 200k values, and nothing when UInt64 arrives quoted. Not worth a special case.
