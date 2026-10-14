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
