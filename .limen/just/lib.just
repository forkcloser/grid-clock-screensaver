# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

# Uniform per-recipe banner, shared across the lint/fix/tools modules via `import`
# (a `mod` can't be depended on, and modules don't inherit the parent's recipes).
# Private → hidden from --list. The module name is passed in because just has no
# current-module variable; depended on with arguments so it prints identically for
# plain *and* shebang recipes, which just otherwise echoes inconsistently (plain
# recipes echo their lines; shebang recipes do not).
_banner mod name:
    @echo "▶ {{ mod }}: {{ name }}"

# go_cgo answers "does THIS project build with cgo?" for every Go recipe —
# `export CGO_ENABLED="{{ go_cgo }}"` in a shebang body, or as a command prefix in
# a plain one. Interpolated into build, test and the per-platform analysis legs so
# they cannot disagree about the nature of the project.
#
# It is a SHELL EXPANSION, not a just value, and that is the entire design: it is
# evaluated when the recipe runs, where a parent's exports are present. Resolving
# it at parse time instead — `export CGO_ENABLED := env('CGO_ENABLED', '0')`, how
# this once read — cannot work: a child module cannot see its parent's variables,
# and env() reads just's PROCESS environment, which never holds one, so a project's
# `export GO_CGO := '1'` was silently discarded and 0 re-exported over it.
#
# Precedence, in order: an explicit CGO_ENABLED on the invocation wins (including
# downgrading a cgo project for a one-off pure-Go run), then the project's GO_CGO,
# then off — because go's own default is cgo ON for native builds wherever a C
# toolchain happens to exist, which would make the same tree behave differently on
# two machines.
go_cgo := '${CGO_ENABLED:-${GO_CGO:-0}}'

# Run CMD once per supported platform (the list below mirrors the canonical
# checksum.supported_envs in aqua.yaml) with CGO disabled: the Go build/dependency graph
# differs per GOOS, so a single native run misses the other platforms' files
# and dependencies. CGO prevents exactly that — loading packages for a foreign
# GOOS needs that platform's C toolchain — so a project that genuinely needs
# cgo declares it (`export GO_CGO := '1'`, or CGO_ENABLED=1 for one invocation)
# and gets one native run only: reduced coverage, announced loudly.
# The same resolution as the build module, so ONE project knob governs every Go
# task — analysis and build agree on whether this project is a cgo project.
_per-goos +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ go_cgo }}" = "1" ]; then
        echo "CGO_ENABLED=1: cross-platform runs are impossible (foreign-GOOS package" >&2
        echo "loading needs that platform's C toolchain) — native platform only." >&2
        {{ cmd }}
    else
        # Native platform FIRST, always: go_install tools build lazily on
        # first use, and `go install` refuses to cross-compile when GOBIN is
        # set (which is how aqua builds Go tools) — so a cold start must
        # trigger that build on the native leg; the foreign legs then merely
        # run the already-built binary.
        # Extend this list together with checksum.supported_envs in aqua.yaml.
        platforms=(darwin linux windows)
        native="$(go env GOHOSTOS)"
        ordered=("$native")
        for goos in "${platforms[@]}"; do
            [ "$goos" = "$native" ] || ordered+=("$goos")
        done
        for goos in "${ordered[@]}"; do
            echo "→ GOOS=$goos"
            CGO_ENABLED=0 GOOS="$goos" {{ cmd }}
        done
    fi
