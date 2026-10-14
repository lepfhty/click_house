# 01 — Avoid copying the response body to check emptiness

- **Status:** proposed
- **Area:** memory
- **Default-safe:** yes (identical behavior)
- **Effort:** XS

## Problem
`ParseJson`, `ParseJsonOj` and `ParseCsv` call `env.body.strip.empty?`. `String#strip`
allocates a full copy of the response just to test for whitespace, briefly doubling the
memory held by the raw body.

- `lib/click_house/middleware/parse_json.rb`
- `lib/click_house/middleware/parse_json_oj.rb`
- `lib/click_house/middleware/parse_csv.rb`

## Evidence
22 MB body: `strip.empty?` 2.8 ms and a 22 MB allocation; `body !~ /\S/` 7 µs, no allocation.

## Proposal
Replace with a non-allocating whitespace check (e.g. `/\S/.match?(env.body)`), shared in
`ResponseBase`. Add a spec covering empty and whitespace-only bodies.
