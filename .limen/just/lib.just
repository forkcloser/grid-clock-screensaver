# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

# Per-recipe banner, imported (a `mod` cannot be depended on). Depended on WITH
# arguments so plain and shebang recipes print it identically.
_banner mod name:
    @echo "▶ {{ mod }}: {{ name }}"

# go_cgo: "does THIS project build with cgo?", shared by build, test and the
# per-platform legs.
#
# It is a SHELL expansion, not a just value, on purpose: a child module cannot
# see its parent's variables and env() reads just's process environment, so
# `export CGO_ENABLED := env('CGO_ENABLED', '0')` here would silently discard a
# project's GO_CGO.
#
# Precedence: CGO_ENABLED on the invocation, then the project's GO_CGO, then
# off — go's own default is cgo on wherever a C toolchain happens to exist.
go_cgo := '${CGO_ENABLED:-${GO_CGO:-0}}'

# Run CMD once per supported platform — every GOOS/GOARCH pair in the canonical
# checksum.supported_envs of aqua.yaml (the list below mirrors it; extend them
# together) — with CGO disabled. The Go build graph is selected by both axes:
# a file built only on linux is invisible to a darwin run, and a file built
# only on amd64 (an _amd64.go, an _amd64.s) is invisible to an arm64 one, so a
# GOOS-only loop at the host's architecture silently skips half the matrix.
# CGO would prevent exactly this — loading packages for a foreign platform
# needs that platform's C toolchain — so a project that genuinely needs cgo
# declares it (`export GO_CGO := '1'`, or CGO_ENABLED=1 for one invocation)
# and gets one native run only: reduced coverage, announced loudly.
_per-platform +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ go_cgo }}" = "1" ]; then
        echo "CGO_ENABLED=1: cross-platform runs are impossible (foreign-platform package" >&2
        echo "loading needs that platform's C toolchain) — native platform only." >&2
        {{ cmd }}
    else
        # Native platform FIRST, always: go_install tools build lazily on
        # first use, and `go install` refuses to cross-compile when GOBIN is
        # set (which is how aqua builds Go tools) — so a cold start must
        # trigger that build on the native leg; the foreign legs then merely
        # run the already-built binary.
        platforms=(darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64)
        native="$(go env GOHOSTOS)/$(go env GOHOSTARCH)"
        ordered=("$native")
        for platform in "${platforms[@]}"; do
            [ "$platform" = "$native" ] || ordered+=("$platform")
        done
        for platform in "${ordered[@]}"; do
            echo "→ GOOS=${platform%/*} GOARCH=${platform#*/}"
            CGO_ENABLED=0 GOOS="${platform%/*}" GOARCH="${platform#*/}" {{ cmd }}
        done
    fi
