# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

default: code mod

# golangci-lint auto-fixes, once per supported platform (see _per-goos in
# lib.just: platform-specific files are only analyzed for the GOOS that
# builds them). The formatter is build-graph-independent and runs last, so the
# fixes' edits end up formatted — but it runs to CONVERGENCE, not once.
#
# `golangci-lint fmt` applies every enabled formatter in a single pass, and the
# set is not confluent: one formatter's output can be work for another (gofumpt
# wanting a blank line that golines' rewrite exposed, say). One pass can
# therefore leave a tree that `fmt --diff` still rejects — so `just fix` would
# report success and `just lint` immediately fail, which is the worst possible
# pairing. Observed on protoc-gen-go output, which needs exactly two passes.
#
# Bounded, because non-convergence has two causes and only one is benign: a
# formatter set that merely needs another pass settles in two or three, while
# two formatters that undo each other never settle. Loop for the first, fail
# loudly for the second instead of hanging CI forever.
code: (_banner "fix go" "go") (_per-goos "golangci-lint run --fix")
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

# Tidy go.mod/go.sum.
mod: (_banner "fix go" "mod")
    go mod tidy

# Update every dependency to its latest version, then tidy.
up: (_banner "fix go" "up") && mod
    go get -u ./...
