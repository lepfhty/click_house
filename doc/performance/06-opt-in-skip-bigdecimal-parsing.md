# 06 — Opt-in: skip BigDecimal for every JSON number

- **Status:** done ([#24](https://github.com/lepfhty/click_house/pull/24))
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

## Implementation
- `config.parse_floats` (default `false`). `Connection#default_params` holds the
  settings the driver sends with every query, now `send_progress_in_http_headers=1` and,
  with `parse_floats`, `output_format_json_quote_decimals=1`. Both GET and POST start
  from it, so `global_params` and per-request params override it and `nil` removes it.
- `ParseJson` merges `decimal_class: nil` and `ParseJsonOj` merges
  `bigdecimal_load: :float` at parse time. The configured `json_load_options` and
  `oj_load_options` are left as they are, so the order of assignments doesn't matter.
- Offline specs for the params on GET and POST and for parsing and casting; a live spec
  checks a `Decimal(38, 10)` keeps all its digits, on 22.9 and 26.3. Specs check the
  class, since `BigDecimal('1.5') == 1.5`.
- Columns the driver doesn't cast (`Dynamic`, `Variant`, `JSON`) and named `Tuple`s keep
  Decimal values as strings, where the default gives `BigDecimal`.
