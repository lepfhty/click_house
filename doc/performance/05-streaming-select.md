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

## Progress output formats
Tested against dockerized 22.9 through 26.3.

- `JSONCompactEachRowWithProgress` exists from 25.2
  ([#75037](https://github.com/ClickHouse/ClickHouse/pull/75037)). It writes one JSON
  object per line: `{"progress":{...}}` about every 100 ms, `{"meta":[...]}`,
  `{"row":[...]}`, then `{"totals":[...]}` and `{"rows_before_limit_at_least":N}` when
  they apply. The last progress line carries the final read stats. That covers types,
  rows, totals, stats and progress in one stream. Fall back to
  `JSONCompactEachRowWithNamesAndTypes` on older servers.
- It works for `readonly=1` users, because the format comes from `default_format` and
  setting it isn't a settings change.
- Its progress lines keep a long select's socket busy, but only without compression.
  26.1 turned `enable_http_compression` on by default, Net::HTTP asks for gzip, and the
  gzip stream holds the lines back until the end, so the read timeout fires. With
  `Accept-Encoding: identity` they stream again. Decide whether to trade network IO for
  that keepalive.
- `X-ClickHouse-Summary` is sent with the first progress line, so for long queries it is
  nearly empty. Read summary stats from the last progress line instead.
- Errors after output starts: 26.x writes an `__exception__` block tagged with the
  `X-ClickHouse-Exception-Tag` header value; 25.x writes the error into the format
  (`http_write_exception_in_output_format`, on by default until 25.11). The status is
  already 200 either way.

## Mid-stream errors in `select_all` today
- A query that fails after a large result starts streaming raises
  `NetworkException: end of file reached` (the server aborts the chunked response), not
  `DbException`.
- A small result that fails partway raises `DbException` with the partial JSON body in
  its message (pending spec in `spec/click_house/offline/responses_spec.rb`).
