# 03 — Same param precedence for GET and POST

- **Status:** done ([#25](https://github.com/lepfhty/click_house/pull/25))
- **Area:** connection
- **Effort:** S

## Problem
`Connection#get` and `Connection#post` build their query params in different orders, so
the `database:` argument wins on one path and loses on the other:

- `get` (`select_all`, `select_one`, `select_value`) merges `database:` over the
  caller's `query:`, then merges the result over `global_params`. The argument always
  wins.
- `post` (`execute`, `insert` and everything built on `execute`) builds
  `query.merge(database: database, **params)`, where `params` is `global_params` plus
  the per-call `params:`. A `database` key in either one beats the argument.

Captured with `stub_clickhouse(database: 'cfg', global_params: { database: 'gp' })`:

| Call | `database` sent |
|------|-----------------|
| `select_all('SELECT 1')` | `cfg` |
| `execute('SELECT 1')` | `gp` |
| `get(body: 'SELECT 1', database: 'arg', query: { database: 'per_call' })` | `arg` |
| `execute('SELECT 1', database: 'arg', params: { database: 'per_call' })` | `per_call` |

Overriding the driver's own `send_progress_in_http_headers` from `global_params` already
works the same on both paths.

Few apps put `database` in `global_params`, so this rarely bites today. It's the same
kind of split as the `global_params` bug fixed in #19, and ticket 06 in
`doc/performance/` needs to add a second driver default
(`output_format_json_quote_decimals`) on both paths.

## Proposal
- Build params for both paths in one private method, in one order:
  1. driver defaults (`send_progress_in_http_headers: 1`);
  2. `config.global_params`;
  3. per-call settings (`query:` for `get`, `params:` for `execute`);
  4. the `database:` argument, last.
- The `database:` argument always decides, and `nil` removes the key. Callers that pass
  `database: nil` (`ping`, `replicas_status`, `databases`, `create_database`,
  `drop_database`) then never send a database, even one set in `global_params`.
- `get` keeps sending settings only when there's a body: `/ping` rejects any query
  string (404 on 26.3, 400 `Empty query` on 22.9). Update the comment in
  `Connection#get`, which mentions only the 404.
- `compose` keeps `.compact`, so `nil` settings still mean "don't send".
- Offline specs in `spec/click_house/offline/requests_spec.rb` for each row of the table
  above, on both paths, plus a driver default overridden from `global_params`.

## Implementation
- `get` already merged `database:` last. `post` now builds
  `query.merge(params, database: database)`, so on both paths the order is driver
  defaults (`Connection#default_params`), `global_params`, per-call settings, then
  `database:`. `nil` removes the key through `compact`.
- The comment in `Connection#get` gives both `/ping` failures.
- Offline specs in `spec/click_house/offline/requests_spec.rb` cover each row of the
  table on both paths and `database: nil`.

## Behavior change
On `execute` and `insert`, a `database` in `global_params` or `params:` no longer
overrides `config.database` or the `database:` argument. Changelog entry under
`## Changed`.

## Out of scope
- `parse_floats` (ticket 06 in `doc/performance/`). It builds on the method added here.
- Sending the database as an `X-ClickHouse-Database` header instead of a query param.
  See below.

## `X-ClickHouse-Database` header
Checked with curl against 22.9.7.34 and 26.3.51.7:

| Request | 22.9 | 26.3 |
|---------|------|------|
| `/ping` or `/replicas_status`, no header, header `default` or a missing database | 200 `Ok.` | 200 `Ok.` |
| `/ping?database=default` | 400 `Empty query` | 404 no handler |
| query, header naming a missing database | `UNKNOWN_DATABASE` | `UNKNOWN_DATABASE` |
| query, `?database=default` plus header `system` | runs in `system` | runs in `system` |

- The health endpoints ignore the header, so it would avoid the query-string failure on
  `/ping`.
- The header beats the query param. Set once on the connection, it would override every
  per-call `database:`, so it would need the same per-request handling as the param,
  with `database: nil` dropping it.
- Queries check the header's database. Set on the connection, it would break
  `create_database` and `databases` before the configured database exists, e.g. the
  README's `click_house:create` task.

It adds a second channel that silently overrides the first and fixes nothing the param
can't, so the driver keeps the query param.
