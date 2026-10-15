#!/usr/bin/env bash
# Tags a release: checks master, the version and CHANGELOG.md, then creates and pushes
# the annotated tag vX.Y.Z. The release workflow creates the GitHub Release from it.
#
# Usage: bin/release.sh [--dry-run]
#   --dry-run  run every check, but don't create or push the tag
set -euo pipefail

dry_run=false
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=true ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."

fail() {
  echo "release: $*" >&2
  exit 1
}

branch=$(git rev-parse --abbrev-ref HEAD)
[[ $branch == master ]] || fail "on branch '$branch', switch to master"

[[ -z $(git status --porcelain) ]] || fail "working tree is not clean"

git fetch --quiet origin master
[[ $(git rev-parse master) == $(git rev-parse origin/master) ]] \
  || fail "local master differs from origin/master, pull or push first"

version=$(ruby -r ./lib/click_house/version -e 'print ClickHouse::VERSION')
tag="v$version"

if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  fail "tag $tag already exists locally, bump lib/click_house/version.rb"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
  fail "tag $tag already exists on origin, bump lib/click_house/version.rb"
fi

notes=$(bin/changelog-section "$version") || fail "CHANGELOG.md has no '# $version' section"
[[ -n $notes ]] || fail "CHANGELOG.md section '# $version' is empty"
if unreleased=$(bin/changelog-section Unreleased) && [[ -n $unreleased ]]; then
  fail "CHANGELOG.md still has entries under '# Unreleased', move them under '# $version'"
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
gem build --silent click_house.gemspec --output "$build_dir/click_house.gem" >/dev/null \
  || fail "gem build failed"

if $dry_run; then
  echo "release: checks passed for $tag (dry run, no tag created)"
  exit 0
fi

git tag --annotate "$tag" --message "Release $tag"
git push origin "refs/tags/$tag"
echo "release: pushed $tag, the release workflow creates the GitHub Release"
