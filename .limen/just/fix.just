# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

default: limen just yaml aqua

# limen itself: repair what `just do lint limen` reports — rewrite drifted
# canonical files, create missing mandatory ones, restore aqua pins and
# regenerate aqua-checksums.json (network, when pins changed). Same LIMEN_BIN
# override as the lint recipe (see lint.just).
limen: (_banner "fix" "limen")
    ${LIMEN_BIN:-limen} fix .

# Repair what `just do lint github` reports — plans first, applies on consent
# (pass -yes for unattended use, -org <name> for the organization). Never in
# the default set, same reasoning as the lint twin.
github *args: (_banner "fix" "github")
    ${LIMEN_BIN:-limen} github fix {{ args }}

just: (_banner "fix" "just")
    #!/usr/bin/env bash
    set -euo pipefail
    # --cached --others --exclude-standard: tracked *and* new untracked files,
    # still honoring .gitignore — so a not-yet-staged file is formatted too.
    # Tracked-but-deleted files are skipped (see `lint just` for the rationale:
    # enumeration is git's, truth is the working tree's).
    # Same pathspecs as `lint just`: literals carry their '**/' twins (git
    # pathspec literals are case-sensitive and do not match across
    # directories), and the hidden .justfile spelling is covered.
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        just --fmt --justfile "$f"
    done < <(git ls-files -z --cached --others --exclude-standard \
        'justfile' '**/justfile' 'Justfile' '**/Justfile' '.justfile' '**/.justfile' '*.just')

yaml: (_banner "fix" "yaml")
    yamlfmt -conf .limen/.yamlfmt

# Regenerate aqua-checksums.json from aqua.yaml — the mutating twin of
# `just do lint aqua` (needs network). In the default set so a plain
# `just do fix` heals the drift the lint default flags.
aqua: (_banner "fix" "aqua")
    aqua --log-level warn update-checksum --prune

# Go fixers live in their own submodule: `just do fix go` runs them all,
# `just do fix go <recipe>` (e.g. `just do fix go mod`) runs one.
mod go 'fix-go.just'
mod rust 'fix-rust.just'
mod homebrew 'fix-homebrew.just'
