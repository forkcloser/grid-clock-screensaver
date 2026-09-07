#!/usr/bin/env bash
# The CHANGELOG.md section for one version — and the assertion that it exists.
#
# goreleaser runs this as a before-hook, so a tag whose notes were never
# written does not release: the GitHub release points at this section rather
# than carrying goreleaser's commit list (v0.1.0's notes were every commit in
# the repository, upstream's 2016 history included).
#
#   scripts/release-notes.sh <version> [is-snapshot]
#
#   version      as goreleaser renders {{ .Version }}: 1.0.0, no leading v.
#   is-snapshot  "true" for a --snapshot build, which has no section of its own
#                and reads [Unreleased] instead.
set -euo pipefail

version="${1:?usage: release-notes.sh <version> [is-snapshot]}"
snapshot="${2:-false}"
changelog="$(dirname "$0")/../CHANGELOG.md"

if [ "$snapshot" = "true" ]; then
    heading='## [Unreleased]'
else
    heading="## [$version]"
fi

# Everything from the heading to the next second-level heading. The heading
# may carry a date suffix ("## [1.0.0] - 2026-09-10"), hence a prefix match.
notes=$(awk -v h="$heading" '
    index($0, h) == 1 { found = 1; next }
    found && /^## /   { exit }
    found             { print }
' "$changelog")

if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
    echo "release-notes.sh: CHANGELOG.md has no '$heading' section, or it is empty — write the release notes before tagging" >&2
    exit 1
fi

printf '%s\n' "$notes"
