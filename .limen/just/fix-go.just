# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

default: code mod

# golangci-lint auto-fixes, once per supported platform (see _per-platform in
# lib.just). The formatter runs LAST and to CONVERGENCE: `golangci-lint fmt`
# applies every formatter in one pass and the set is not confluent (one
# formatter's output can be another's work), so a single pass can leave a tree
# `fmt --diff` still rejects — `just fix` green, `just lint` red. Bounded,
# because two formatters undoing each other never settle: loop for the benign
# case, fail loudly for the other.
code: (_banner "fix go" "go") (_per-platform "golangci-lint run --fix")
    #!/usr/bin/env bash
    set -euo pipefail
    max=5
    pass=0
    # Check first: an already-formatted tree costs one --diff and no rewrite.
    while ! golangci-lint fmt --diff >/dev/null 2>&1; do
        pass=$((pass + 1))
        if [ "${pass}" -gt "${max}" ]; then
            echo "formatters did not converge after ${max} passes — they are fighting each other." >&2
            echo "The residual diff below reverses on the next pass; fix the formatter config." >&2
            golangci-lint fmt --diff >&2 || true
            exit 1
        fi
        golangci-lint fmt
    done

# Tidy go.mod/go.sum, for the module and for tools/ (the analyzers' module).
mod: (_banner "fix go" "mod")
    go mod tidy
    go -C tools mod tidy

# Update every dependency to its latest version, then tidy.
up: (_banner "fix go" "up") && mod
    go get -u ./...
