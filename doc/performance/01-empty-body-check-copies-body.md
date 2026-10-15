# 01 — Avoid copying the response body to check emptiness

- **Status:** in progress
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

## Implementation
`ResponseBase#blank_body?` matches `/[^\0\t\n\v\f\r ]/`, the characters `String#strip`
keeps, so it gives the same answer as `strip.empty?` without copying the body. Bodies the
regexp can't scan without raising (invalid or non-ASCII-compatible encoding) fall back to
`strip.empty?`, so error behavior is unchanged too; a fuzz over 1.8M byte strings in nine
encodings found no difference in results or exceptions on Ruby 2.7 and 3.3. Specs in
`spec/click_house/middleware/response_parsers_spec.rb` pin empty, whitespace, NUL, non-ASCII
whitespace, binary, invalid UTF-8 and nil bodies.

On a 22 MB body the check no longer allocates (was a 22 MB copy). It is slower than
`strip` only for bodies made of megabytes of leading whitespace (~10 ns per byte), which
ClickHouse doesn't send.
