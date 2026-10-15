# 01 — Replace the release script

- **Status:** proposed
- **Area:** release process
- **Effort:** S

## Problem
`make release` runs `bin/release.sh`, which builds the gem and runs `gem push`. The
gemspec still uses upstream's gem name, `click_house`, so the script either fails (the
fork doesn't own that name on RubyGems) or, with credentials that can push to it,
publishes over upstream's gem. CONTRIBUTING warns against running it, but the command is
still one `make` target away, and `make help` lists it.

CONTRIBUTING already describes the fork's actual process: bump the version, move the
`Unreleased` CHANGELOG entries, merge, tag `vX.Y.Z` and push the tag. Nothing automates
or checks it.

## Decision needed: how apps get the fork
- **Git source pinned to a tag (recommended).** Apps declare
  `gem 'click_house', git: 'https://github.com/<owner>/click_house.git', tag: 'vX.Y.Z'`.
  No gem server or credentials, and it's how the main app already consumes other forked
  gems. Bundler builds the gem from the gemspec, so `spec.files` must keep working from a
  git checkout.
- **Private gem server.** Only worth it if apps need version constraints (`~> 2.2`)
  rather than exact tags.
- **New public gem name.** Only if people outside the main app will use the fork.

Also decide where the repository lives. It is under a personal account; a gem the main
app depends on may belong in the organization's account, alongside its other forks.
Moving it first avoids changing every app's `Gemfile` later.

## Proposal (for the git-tag option)
- Replace `bin/release.sh` with a script that:
  - checks it is on an up-to-date `master` with a clean tree;
  - reads `ClickHouse::VERSION` and fails if tag `vX.Y.Z` already exists;
  - fails if `CHANGELOG.md` has no `# X.Y.Z` section, or still has entries under
    `Unreleased`;
  - runs `gem build` as a check that the gemspec builds, then deletes the `.gem`;
  - creates an annotated tag and pushes it, and never runs `gem push`.
- Point `make release` at it and update `make help`.
- Update CONTRIBUTING's release section to say "run `make release`" and how apps pin
  the tag. Remove the warning about the old script.
- Optional: a CI job on tag push that checks the tag matches `ClickHouse::VERSION`.

## Out of scope
- Choosing the first fork version number (CONTRIBUTING says to continue from `2.1.2`).
- Publishing to any gem server.
