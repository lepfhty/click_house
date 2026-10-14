#!/usr/bin/env bash
# Runs benchmark/run.rb for each Faraday version and JSON parser, appending to
# benchmark/results.csv. Extra arguments are passed through, e.g. --note "..." or --port 28123.
# A failing combination is reported and skipped; the script exits non-zero if any failed.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
for gemfile in Gemfile_faraday1 Gemfile_faraday2; do
  for parser in json oj; do
    if ! BUNDLE_GEMFILE="$gemfile" bundle exec ruby benchmark/run.rb --parser "$parser" "$@"; then
      failed+=("$gemfile/$parser")
    fi
  done
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "failed: ${failed[*]}" >&2
  exit 1
fi
