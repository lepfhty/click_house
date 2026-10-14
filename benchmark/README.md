# Benchmarks

`benchmark/run.rb` measures the driver and appends one row per scenario to
`benchmark/results.csv`, which is committed so results accumulate over time.

## Running

```sh
# everything, against a local server (see CONTRIBUTING.md for starting one)
CLICKHOUSE_PORT=28123 make faraday1 bench
CLICKHOUSE_PORT=28123 make faraday2 bench ARGS="--parser oj"

# every Faraday version × JSON parser combination
make bench-matrix ARGS="--port 28123 --note 'baseline'"

# no server needed
make faraday2 bench ARGS="--suite offline"

# try something without recording it
make faraday2 bench ARGS="--only 'cast DateTime' --no-record"
```

Options: `--suite all|offline|e2e`, `--parser json|oj`, `--rows N` (default 100000),
`--iterations N` (default 5), `--warmup N` (default 1), `--port`, `--only REGEX`,
`--note TEXT`, `--output PATH`, `--no-record`. To benchmark with YJIT, set
`RUBY_YJIT_ENABLE=1`.

## Scenarios

| Suite | Scenario | What it measures |
|---|---|---|
| offline | `parse_json_mixed` | The configured JSON parser middleware on a FORMAT JSON body |
| offline | `cast <type>` | `ResultSet#to_a` on a single column of that type |
| offline | `serialize_cast_mixed` | `ResultSet#serialize`: casting Ruby values for INSERT |
| offline | `dump_each_row_mixed` | The configured serializer building a JSONEachRow body |
| e2e | `insert_json_each_row`, `insert_compact` | `Connection#insert` over HTTP |
| e2e | `select_all_raw`, `select_all_cast` | `select_all` without and with type casting |
| e2e | `select_value_x200` | 200 trivial queries: per-request overhead |

`rows_per_sec` is queries per second for `select_value_x200`. `allocations` counts
objects allocated per iteration (median). Peak memory isn't measured.

## What a row identifies

Releases are infrequent, so the version number isn't enough to tell runs apart. Each row
records:

- **Code:** `git_sha` is the commit benchmarked. `git_dirty` is true when `lib/`,
  `benchmark/`, the gemspec or the Gemfiles had uncommitted changes, and `git_diff_sha`
  fingerprints those changes so runs from different uncommitted states can be told
  apart. `gem_version` and `note` are for humans.
- **Runtime:** Ruby version, platform and YJIT; Faraday and adapter versions; the JSON
  parser and the json, oj and activesupport versions; the ClickHouse server version
  (end-to-end rows only).
- **Machine:** CPU model and core count, and OS. Timings are only comparable between
  rows from the same machine.

All rows from one invocation share a `run_id`.

## Recording results for a change

1. Commit the change itself.
2. Run the benchmarks from that clean commit, so rows carry its SHA and `git_dirty=false`.
3. Commit `benchmark/results.csv` separately (or amend it into the PR). Changes to
   `results.csv` never mark a run dirty.

For a dependency upgrade, run the matrix before and after updating the lockfiles; the
version columns show what changed.

## Changing the CSV

Add new columns at the end of `Bench::Recorder::HEADER` and backfill existing rows (empty
values are fine). The recorder refuses to append when the file's header doesn't match.
