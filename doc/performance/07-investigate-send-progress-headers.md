# 07 — Make `send_progress_in_http_headers` configurable

- **Status:** proposed (investigation done)
- **Area:** compatibility / latency
- **Default-safe:** keep the default on; add a way to turn it off
- **Effort:** S

## Observation
`Connection#compose` (POST) and `Connection#get` (GET, used by every `select_*`) add
`send_progress_in_http_headers=1` to every request (`lib/click_house/connection.rb`).

## Investigation
Run against dockerized ClickHouse 22.9.7 (the CI version), 24.6.2 and 25.8.33, plus
stock `nginx:1.27` as a reverse proxy. All three versions behaved the same.

| Question | Finding |
|---|---|
| Is the setting needed for `X-ClickHouse-Summary`? | **No.** The summary header is sent without it for selects and inserts, with identical values. Nothing in `lib/` reads `X-ClickHouse-Progress`. |
| Does it break `readonly=1` users? | **Yes, for every query.** `Code: 164 ... Cannot modify 'send_progress_in_http_headers' setting in readonly mode`. Reproduced through the driver. `readonly=2` users are fine. Sending `=0` is accepted for `readonly=1` users (it matches the default). |
| Cost on long queries | About 10 `X-ClickHouse-Progress` headers per second, ~190 B each. A 20 s query gave the driver 194 entries, 37 KB of headers, which is about 7 MB per hour of query time, buffered in memory. |
| Proxies | Behind stock nginx (`proxy_buffer_size` 4k), a 5 s query returns **502 "upstream sent too big header"** after ~1.8 s. Without the setting the same query returns 200. |
| What it does for clients | **It keeps the socket busy.** Without it, the server sends nothing until the result is ready, so a query slower than the client read timeout fails with `Net::ReadTimeout`. With it, the same query succeeds. The driver's default `timeout` is nil, which leaves Net::HTTP's 60 s read timeout, so today queries over 60 s work only because of this setting. Idle timeouts on load balancers presumably benefit the same way. |
| Errors after headers are sent | With the setting, a query that fails partway returns `200 OK` but still carries `X-ClickHouse-Exception-Code`. The driver checks that header, so it still raises `DbException`. Proxies or tools that look only at the status code see a success. |

### Existing workaround is partial
`global_params: { send_progress_in_http_headers: nil }` removes the param for `execute` and
`insert` (POST, through `compose` and `.compact`). It does **not** affect `select_all`,
`select_one` or `select_value`, because `Connection#get` sets the param unconditionally.

## Conclusion
The setting does two jobs: it is a keep-alive for long queries, and it is a compatibility
hazard for `readonly=1` users and for proxies with small header buffers. Removing it by
default would break every query slower than the read timeout for every user, which is the
larger population. So the default stays, and users who need to can turn it off.

## Proposal
- Add `config.send_progress_in_http_headers` (default `true`). When false, omit the param
  on both GET and POST. Make `Connection#get` respect it, and respect a
  `global_params` override, the same way `compose` does.
- README: say when to turn it off (`readonly=1` users; behind nginx or other proxies
  with small header buffers) and that callers should then set `timeout` above their
  longest query.
- Specs: params sent for each setting value, for GET and POST.

## Considered and not proposed
- Retrying automatically without the param after a `READONLY` (164) error: it's magic,
  costs an extra round trip, and hides the configuration problem.
- Switching selects to `JSONCompactEachRowWithProgress` instead (see below).

## Progress output formats
Investigated whether the `*WithProgress` output formats could replace the header setting,
since they report progress in the response body instead of headers. Tested against
dockerized 22.9, 24.6, 24.12, 25.1, 25.3, 25.8, 26.1, 26.2 and 26.3.

### Availability
- `JSONCompactEachRowWithProgress` (and `JSONCompactStringsEachRowWithProgress`) were
  added in 25.2 ([#75037](https://github.com/ClickHouse/ClickHouse/pull/75037)): absent
  in 25.1, present in 25.3.
- `JSONEachRowWithProgress` exists in all tested versions, but only writes progress
  "whenever the progress happens" since 25.1
  ([#73834](https://github.com/ClickHouse/ClickHouse/pull/73834)). On 24.6 a long
  aggregation sends nothing until the end.

### Output (26.3)
One JSON object per line: `{"progress":{...}}` lines (every ~100 ms), `{"meta":[...]}`,
`{"row":[...]}`, then `{"totals":[...]}` and `{"rows_before_limit_at_least":N}` when
applicable. The last progress line carries the final read stats.

### Findings
| Question | Finding |
|---|---|
| Works for `readonly=1` users? | Yes. The format comes from `default_format`, which isn't a setting change. |
| Keeps a long SELECT alive without the header? | On 25.8, yes: first bytes at 0.1 s, a 5 s aggregation survives a 2 s read timeout. **On 26.1+, not by default** (next row). |
| Interaction with compression | 26.1 turned `enable_http_compression` on by default (25.8 has it off). Net::HTTP asks for gzip, so with Faraday 2 the server gzips the response, and the compressed stream holds the progress lines back until the end: the 2 s read timeout fires. With `Accept-Encoding: identity` the lines stream again. The header setting is unaffected: the driver as-is survives a 2 s timeout on 26.3 with gzip, on Faraday 1 and 2. |
| Keeps a long INSERT … SELECT alive? | **No.** There are no result rows, so no body is written; the 2 s read timeout fires. With the header setting the same insert returns 200. The same applies to DDL and mutations run with `mutations_sync`. |
| Summary header | Sent with the first progress line, so `X-ClickHouse-Summary` is nearly empty for long queries (read_rows 104M of 6B). `Response::Summary` and the logged read stats would have to come from the last progress line instead. |
| Errors after output starts | 26.x writes an `__exception__` block tagged with the `X-ClickHouse-Exception-Tag` header value; 25.x writes the error into the format (`http_write_exception_in_output_format`, default 1 until 25.11). Either way the status is already 200, so the driver would need new detection code. |

### Recommendation: don't switch selects to it
- It can't replace the header setting: it only covers queries that return rows, needs
  25.2+, and loses its keepalive on 26.1+ unless compression is turned off for the request.
- It would rewrite the response path: line-delimited parsing, a new place to read summary
  stats from, new mid-stream error detection, and `ResultSet#data` changing from hashes to
  arrays unless converted back. Older servers would still need the current path, so the
  driver would carry two.
- Keep the plan above: make `send_progress_in_http_headers` configurable, default on.

### Where it does fit
The streaming select API (ticket 05) is new, so it can use a line-delimited format without
breaking anything. On 25.2+ `JSONCompactEachRowWithProgress` gives types, rows, totals,
final stats and progress in one stream. Ticket 05 should decide how to handle compression
(the keepalive needs `Accept-Encoding: identity`, which costs network IO) and fall back to
`JSONCompactEachRowWithNamesAndTypes` on older servers.

### Existing gaps found along the way
- A query that fails after a large result starts streaming surfaces as
  `NetworkException: end of file reached` (the server aborts the chunked response), not
  `DbException`.
- A small result that fails mid-way raises `DbException` with the partial JSON body as its
  message.
