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
4. Add a line under `Unreleased` in `CHANGELOG.md` for any user-visible change.

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

## Dependencies

The gem's `Gemfile.lock` only affects this repository's own tests. Apps resolve
dependencies through their own lockfiles. Bump it when tests need a newer version, and
change gemspec constraints only when one blocks a real upgrade.

## Releases

Apps install the fork from git, pinned to a release tag:

```ruby
gem 'click_house', git: 'https://github.com/lepfhty/click_house.git', tag: 'v2.2.0'
```

To release:

1. Bump `lib/click_house/version.rb` following semver, continuing from `2.1.2`.
2. Move the `Unreleased` entries in `CHANGELOG.md` under the new version.
3. Merge to `master`, then tag the merge commit `vX.Y.Z` and push the tag.

Don't run `make release` or `bin/release.sh`: they push to RubyGems under the upstream
gem's name.

## Upstream

- **Pulling from upstream:** `git fetch upstream` occasionally. If anything worth having
  has landed, merge `upstream/master` into a branch and open a PR in the fork as usual.
- **Sending changes upstream:** optional. If a merged change is useful to everyone and
  self-contained, cherry-pick its commits onto `upstream/master` in a new branch and
  open a PR against `shlima/click_house`. Don't hold fork work back waiting on the answer.
