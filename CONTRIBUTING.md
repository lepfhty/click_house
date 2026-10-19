# Contributing to this fork

This is Tenjin's fork of [shlima/click_house](https://github.com/shlima/click_house).
Upstream has been inactive since 2022, so the fork is developed as its own project.
We track upstream and send changes back when it's convenient, but we never wait on it.

## Principles

- **Compatible defaults first, fast defaults second.** The driver runs against many
  ClickHouse versions, user permissions, proxies and Ruby setups. A change may alter
  default behavior only if callers see identical results. Anything that changes returned
  data, depends on a server setting, adds a dependency, or trades CPU for network ships
  as an opt-in config option.
- **One change per PR.** A PR does one thing and includes its specs. Refactors that
  prepare for a change go in their own PR or commit, with no behavior change.
- **Evidence for performance work.** Performance PRs include before/after numbers and
  how to reproduce them.

## Workflow

1. Branch from `master`: `rn/{slug}_tenjin_{ticketid}` (use your own initials).
2. Commit with [Conventional Commits](https://www.conventionalcommits.org/):
   `type(scope): summary`, e.g. `perf(types): cache time zone per column`.
3. Open a PR against this fork's `master`, never against upstream by accident. GitHub
   defaults a fork's PRs to the parent repository, so check the base repository.
4. For any user-visible change, add a line at the end of its category under `Unreleased`
   in `CHANGELOG.md`, starting with a link to the PR. Categories go in the order
   `## Changed`, `## Fixed`, `## Added`, `## Performance`; add one if it's missing.

If one change depends on another that hasn't merged yet, cut the second branch from the
first and target the first branch in the PR. Retarget it to `master` once the first
merges.

## Testing

Start ClickHouse with `make dockerize`, which runs `docker-compose up` and listens on
port 8123. Then run the suite for both Faraday versions, with both JSON parsers:

```sh
make faraday1 bundle && make faraday2 bundle
make faraday1 rspec
make faraday2 rspec
make faraday1 oj rspec
make faraday2 oj rspec
bundle exec rubocop
```

Specs tagged `:offline` run without a server (`bundle exec rspec --tag offline`). To
cover a response that's hard to get from a real server, build a connection with
`stub_clickhouse(status:, headers:, body:)` from `spec/support/stub_clickhouse.rb`, tag
the example `:offline`, and check what was sent with `clickhouse_requests`.

CI runs this matrix on every push. When adding Ruby or ClickHouse versions to CI:

- Add each version in its own PR. If a new version surfaces failures, fix them in
  earlier PRs so the CI change itself is green.
- ClickHouse images from 24.x on lock out the `default` user unless the container sets
  `CLICKHOUSE_SKIP_USER_SETUP=1`.
- The gem still supports Ruby 2.7 (`required_ruby_version`). Don't use newer Ruby APIs
  without a fallback, or raise the minimum in a dedicated PR.

## Performance work

Candidate performance changes are tracked as tickets in
[`doc/performance/`](doc/performance/README.md), one file per ticket with a status line
(`proposed`, `accepted`, `in progress`, `done`, `rejected`). Update the ticket and the
index table when you pick one up or finish it, and link the PR.

Measure with the benchmark tool in [`benchmark/`](benchmark/README.md). It appends
results to `benchmark/results.csv`, tagged with the commit, dependency versions,
ClickHouse version and machine. Use synthetic data; don't commit customer data or
production schemas.

## Maintenance work

Tooling, test and release-process work that doesn't change the driver's behavior is
tracked the same way in [`doc/maintenance/`](doc/maintenance/README.md).

## Dependencies

The gem's `Gemfile.lock` only affects this repository's own tests. Apps resolve
dependencies through their own lockfiles. Bump it when tests need a newer version, and
change gemspec constraints only when one blocks a real upgrade.

## Releases

A release is a git tag. No gem is published anywhere: apps install the fork from git,
pinned to a release tag, and Bundler builds the gem from the gemspec:

```ruby
gem 'click_house', git: 'https://github.com/lepfhty/click_house.git', tag: 'vX.Y.Z'
```

To release:

1. In a PR, bump `lib/click_house/version.rb` following semver from the latest `v*` tag,
   and move the `Unreleased` entries in `CHANGELOG.md`, with their `##` headings, under a
   new `# X.Y.Z` heading, leaving `# Unreleased` empty.
   Within each category, order entries by how many users they affect, most first, so
   anyone upgrading sees what's likely to touch their code before the edge cases.
2. Merge it, then on an up-to-date `master` run `make release`.

`make release` runs `bin/release.sh`, which checks that `master` is clean and matches
`origin/master`, that tag `vX.Y.Z` doesn't exist yet, that `CHANGELOG.md` has a
`# X.Y.Z` section and nothing left under `Unreleased`, and that the gem builds. It then
creates the annotated tag `vX.Y.Z` and pushes only that tag. `make ARGS="--dry-run"
release` runs the checks without tagging.

Pushing the tag triggers the release workflow (`.github/workflows/release.yml`), which
checks the tag matches `ClickHouse::VERSION` and is on `master`, then creates the GitHub
Release with the version's `CHANGELOG.md` section as its notes. `bin/release.sh` runs
the same checks before tagging, so a failed run is usually transient: rerun the job. A
missing Release breaks nothing, since apps pin the tag.

## Upstream

- **Pulling from upstream:** `git fetch upstream` occasionally. If anything worth having
  has landed, merge `upstream/master` into a branch and open a PR in the fork as usual.
- **Sending changes upstream:** optional. If a merged change is useful to everyone and
  self-contained, cherry-pick its commits onto `upstream/master` in a new branch and
  open a PR against `shlima/click_house`. Don't hold fork work back waiting on the answer.
