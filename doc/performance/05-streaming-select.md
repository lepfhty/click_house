# 05 — Streaming select API

- **Status:** proposed
- **Area:** memory
- **Default-safe:** yes (new, additive API)
- **Effort:** M

## Problem
`select_all` buffers the whole response, parses it into one Hash per row (keys repeated
per row), and casts in place. Peak memory is roughly raw body + parsed rows + cast values,
which makes large exports impractical.

## Evidence
200k rows × 6 columns: `JSON` 22.2 MB vs `JSONCompact` 16.2 MB (27% smaller); parse
0.21 s vs 0.14 s (35% faster).

## Proposal
- Add `select_each(sql) { |row| ... }` (and/or return an `Enumerator`) using
  `FORMAT JSONEachRow` or `JSONCompactEachRow` and Faraday's `on_data` streaming
  callback, so memory stays constant regardless of result size.
- Get column types up front (e.g. `JSONCompactEachRowWithNamesAndTypes`) so rows can be
  cast with the existing `Ast` and `Type` machinery.
- Leave `select_all` unchanged.

## Open questions
- `on_data` support varies by Faraday adapter and version; define fallback behavior.
- Mid-stream server errors arrive in the body after a 200 status; detect them and raise.
- How summary and statistics are exposed when streaming.
