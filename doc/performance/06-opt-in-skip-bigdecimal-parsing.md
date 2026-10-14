# 06 — Opt-in: skip BigDecimal for every JSON number

- **Status:** proposed
- **Area:** cpu / memory
- **Default-safe:** no → opt-in
- **Effort:** S

## Problem
The default `json_load_options: { decimal_class: BigDecimal }` (and Oj's
`bigdecimal_load: :bigdecimal`) turns every fractional JSON number into a `BigDecimal`,
including Float64 columns, which `FloatType` then converts back to `Float`.

## Evidence
22 MB body: `JSON.parse` 0.34 s with `decimal_class` vs 0.21 s without (+60%), plus a
`BigDecimal` allocation per float.

## Why not on by default
Raw `select_all(...).data` would return Float64 values as `Float` instead of
`BigDecimal`. Removing `decimal_class` without asking the server to quote decimals would
also lose precision on `Decimal` columns.

## Proposal
- Opt-in config (e.g. `config.fast_decimals = true`) that sends
  `output_format_json_quote_decimals=1` and drops `decimal_class` /
  `bigdecimal_load`. `DecimalType#cast` already accepts strings.
- Same `readonly=1` caveat as other server settings; document it.
- Alternatively, just document the trade-off, since `json_load_options` is already
  configurable.
