# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

default: code vet mod vuln licenses

# golangci-lint, once per supported platform (see _per-platform in lib.just:
# platform-specific files are only analyzed for the GOOS/GOARCH that builds
# them).
# The formatter is build-graph-independent and runs once. The last step
# enforces the suppression doctrine (book/per-language.md, "silencing a
# finding"): a finding is silenced by its rule, never by its linter.
code: (_banner "lint go" "go") _golangci-toolchain-check (_per-platform "golangci-lint run") _suppression-check
    golangci-lint fmt --diff

# Polices the shape the book requires (per-language.md, "silencing a
# finding"): nolintlint checks a directive's form, not which linter it names,
# and bag linters (revive, gosec, staticcheck) must be silenced per rule.
# Tracked Go files only.
[private]
_suppression-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    # ban <message> <pattern> [<allowed-pattern>]: every tracked Go line matching
    # <pattern> and not <allowed-pattern> is a violation.
    ban() {
        local hits
        hits="$(git grep -nE "$2" -- '*.go' || true)"
        if [ -n "$hits" ] && [ -n "${3:-}" ]; then hits="$(printf '%s\n' "$hits" | grep -vE "$3" || true)"; fi
        if [ -n "$hits" ]; then printf '%s\n' "$hits" >&2; echo "$1" >&2; fail=1; fi
    }
    ban 'blanket revive suppression is banned — use //revive:disable-next-line:<rule> (or a disable/enable block)' \
        'nolint:[a-z, ]*revive'
    ban 'blanket gosec suppression is banned — use gosec'"'"'s own // #nosec G### -- reason (on its own comment line when combined with a //nolint)' \
        'nolint:[a-z, ]*gosec'
    ban '#nosec must name its rule(s): // #nosec G### -- reason' \
        '#nosec' '#nosec( G[0-9]{3})+( --|[[:space:]]*$)'
    ban 'staticcheck suppressions must name the check in the reason: //nolint:staticcheck // SA####: reason' \
        'nolint:[a-z, ]*staticcheck' '(^|[^A-Z])(SA|ST|S|QF)[0-9]{4}([^0-9]|$)'
    ban 'bare //nolint is banned — name the linter (or, for a bag linter, the rule)' \
        '//nolint(:all)?([^a-z:]|$)'
    exit "$fail"

# golangci-lint embeds Go's type checker, so a golangci built with go1.N cannot
# analyze a go1.N+1 toolchain: it panics with "file requires newer Go version".
# The two pins move in lockstep — golangci first (a release built with the
# newer Go), then golang/go — and this check turns the panic into that
# instruction. The canonical renovate.json groups the two bumps for the same
# reason. Compares major.minor only: patch releases share a language version.
[private]
_golangci-toolchain-check:
    #!/usr/bin/env bash
    set -euo pipefail
    built="$(golangci-lint version 2>/dev/null | sed -nE 's/.*built with go([0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
    toolchain="$(go env GOVERSION | sed -nE 's/^go([0-9]+\.[0-9]+).*/\1/p')"
    if [ -n "$built" ] && [ -n "$toolchain" ] && [ "$(printf '%s\n%s\n' "$toolchain" "$built" | sort -V | tail -n 1)" != "$built" ]; then
        echo "golangci-lint was built with go${built} but the pinned toolchain is go${toolchain}:" >&2
        echo "it cannot analyze a newer Go. Bump golangci/golangci-lint to a release built with go${toolchain}" >&2
        echo "(just do tools update golangci-lint) BEFORE bumping golang/go." >&2
        exit 1
    fi

# The two `go vet` analyzers golangci-lint cannot run: its package loader never
# hands analyzers a package's non-Go files, so asmdecl (assembly against the Go
# declarations it implements) and buildtag (constraints in non-Go files) report
# nothing through it whatever the govet configuration says — even
# `enable-all`. Broken amd64 assembly passed `lint go` on the amd64 CI legs
# for exactly that reason. Scoped to those two on purpose: `go vet` reads
# neither .golangci.yml nor //nolint, so any analyzer that overlaps with
# golangci's govet would re-report findings a project deliberately silenced,
# and the same exception would then have to be written twice. Every
# supported platform, like the rest (see _per-platform in lib.just); vet
# type-checks without an assembler or C toolchain, so each leg is a few
# seconds. Note `go test` is not a backstop here: the vet subset it runs
# excludes both analyzers.
vet: (_banner "lint go" "vet") (_per-platform "go vet -asmdecl -buildtag ./...")

# go.mod/go.sum tidiness, for the module and for tools/ (the Go-built tools'
# own module — see _go-tool in lib.just). Fails printing the diff; `just do fix
# go mod` repairs.
mod: (_banner "lint go" "mod")
    go mod tidy -diff
    go -C tools mod tidy -diff

# Known-vulnerability scan against the Go vulnerability database (network:
# govulncheck fetches vuln.go.dev), once per supported platform (see _per-platform
# in lib.just: call paths and dependencies differ by platform).
vuln: (_banner "lint go" "vuln") (_go-tool "govulncheck" "golang.org/x/vuln/cmd/govulncheck") (_per-platform "build/tools/govulncheck ./...")

# Dependency license compliance, once per supported platform (see _per-platform in
# lib.just: each platform pulls its own dependencies). Extra flags (typically
# --ignore=<module> for the false positives of google/go-licenses#186): export
# LINT_GO_LICENSES_FLAGS from the root Justfile.
#
# GOROOT is passed explicitly because go-licenses recognizes stdlib packages by
# their location under GOROOT, reading its default from its own build. _go-tool
# compiles it with the pinned toolchain, so the two agree by construction; the
# explicit value keeps that true even when a project overrides GOROOT.
licenses: (_banner "lint go" "licenses") (_go-tool "go-licenses" "github.com/google/go-licenses/v2") (_per-platform 'GOROOT="$(go env GOROOT)" build/tools/go-licenses check --include_tests --allowed_licenses=Apache-2.0,BSD-2-Clause,BSD-3-Clause,MIT ${LINT_GO_LICENSES_FLAGS:-} ./...')

# Every bounds check the compiler could not eliminate. Informational: never
# fails, native arch only (BCE is arch-specific), not in the default set.
bce: (_banner "lint go" "bce")
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Bounds Check Elimination Report"
    echo "================================"
    echo ""
    # Keep compiler diagnostics only (file.go:line:col:): the build's other
    # chatter — package banners, a CGO link's `ld: warning` — must not count.
    output=$(go build -gcflags='-d=ssa/check_bce/debug=1' ./... 2>&1 | grep -E '\.go:[0-9]+:[0-9]+: ' || true)
    # Generic instantiations compile in the CALLER's package, so the compiler
    # also reports positions inside GOROOT (slices.SortFunc & co) and the module
    # cache (a generic dependency). Real checks in the binary, but not this
    # module's code to change — keep the module's own files only. Positions are
    # relative to the module root, so anything outside it starts with "../" (or
    # is absolute).
    external=$(echo "$output" | grep -cE '^(\.\./|/)' || true)
    output=$(echo "$output" | grep -vE '^(\.\./|/)' || true)
    if [ "$external" != 0 ]; then
        echo "(${external} in generic instantiations from GOROOT/module cache omitted — not this module's code)"
        echo ""
    fi
    if [ -z "$output" ]; then
        echo "No bounds checks detected (BCE fully eliminated)."
    else
        total=$(echo "$output" | wc -l | tr -d ' ')
        echo "Total: $total bounds checks"
        echo ""
        echo "By file:"
        echo "$output" | sed 's/:.*$//' | sort | uniq -c | sort -rn
        echo ""
        echo "Details:"
        echo "$output" | sort
    fi

# Escape-analysis and inlining report — both come from the same compiler pass
# (-gcflags=-m): values the compiler moved to the heap (the prime source of GC
# pressure) and functions it refused to inline, with the reason. Informational
# like bce: never fails, native architecture only, not in the default set.
escape: (_banner "lint go" "escape")
    #!/usr/bin/env bash
    set -euo pipefail
    # Same filters as bce: compiler diagnostics only, then drop positions
    # inside GOROOT / the module cache (generic instantiations compiled into
    # this module's packages).
    output=$(go build -gcflags='-m' ./... 2>&1 | grep -E '\.go:[0-9]+:[0-9]+: ' || true)
    external=$(echo "$output" | grep -cE '^(\.\./|/)' || true)
    output=$(echo "$output" | grep -vE '^(\.\./|/)' || true)
    heap=$(echo "$output" | grep -E 'escapes to heap|moved to heap' || true)
    noinline=$(echo "$output" | grep 'cannot inline' || true)
    echo "Escape Analysis Report"
    echo "======================"
    if [ "$external" != 0 ]; then
        echo "(${external} lines in generic instantiations from GOROOT/module cache omitted — not this module's code)"
        echo ""
    fi
    if [ -z "$heap" ]; then
        echo "No heap escapes."
    else
        echo "Total: $(echo "$heap" | wc -l | tr -d ' ') heap escapes"
        echo ""
        echo "By file:"
        echo "$heap" | sed 's/:.*$//' | sort | uniq -c | sort -rn
        echo ""
        echo "$heap" | sort
    fi
    echo ""
    echo "Inlining Failures"
    echo "================="
    if [ -z "$noinline" ]; then
        echo "None."
    else
        echo "Total: $(echo "$noinline" | wc -l | tr -d ' ') functions the compiler could not inline"
        echo ""
        echo "$noinline" | sort
    fi

# Unreachable functions, by whole-program call-graph analysis (deeper than the
# per-package `unused` linter in golangci). -test keeps library-only repos
# analyzable (test binaries serve as roots) and stops dead code from hiding
# behind test-only callers. Informational: native only, not in the default set.
deadcode: (_banner "lint go" "deadcode") (_go-tool "deadcode" "golang.org/x/tools/cmd/deadcode")
    build/tools/deadcode -test ./...
