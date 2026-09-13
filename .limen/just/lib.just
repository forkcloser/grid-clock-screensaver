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
        platforms=(darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64)
        for platform in "${platforms[@]}"; do
            echo "→ GOOS=${platform%/*} GOARCH=${platform#*/}"
            CGO_ENABLED=0 GOOS="${platform%/*}" GOARCH="${platform#*/}" {{ cmd }}
        done
    fi

# The native build of one tools/go.mod tool into build/tools/, shared by
# _go-tool and the tools recipes (`{{ go_tool_build }} <pkg>`). GOOS/GOARCH
# cleared: a per-platform leg would cross-compile the tool itself (exec format
# error). Directory form of -o: go names the binary itself, which on windows
# means the .exe suffix the loader needs — git-bash then resolves the bare
# build/tools/<name> the recipes call to it. (go strips a /vN major suffix
# when naming, so github.com/google/go-licenses/v2 lands as go-licenses.)
# -o is resolved relative to -C.
go_tool_build := "mkdir -p build/tools && GOOS='' GOARCH='' go -C tools build -o '../build/tools/'"

# Every Go-built tool the recipes run — the Go-source analyzers and the rest
# alike — is a `tool` directive in tools/go.mod, a module of its own, built
# natively ONCE into build/tools/ by the pinned go (book/tooling.md, "Go-built
# tools are go.mod tools"). Never `go tool <name>` from a per-platform leg.
# A tools/go.mod without the directive fails with the recipe that adds it.
# Recipes depend on this with the tool's name and package, then call
# build/tools/<name>.
_go-tool name pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! grep -qE '^(tool[[:space:]]+)?[[:space:]]*{{ pkg }}([[:space:]]|$)' tools/go.mod 2>/dev/null; then
        echo "tools/go.mod lacks 'tool {{ pkg }}' — add it: just do tools add {{ pkg }} (see book/tooling.md)" >&2
        exit 1
    fi
    {{ go_tool_build }} '{{ pkg }}'
