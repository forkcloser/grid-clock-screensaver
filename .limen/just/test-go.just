# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

default: unit

# `go test` runs funnel through gotestsum: same exit semantics, readable live
# output (its format is gotestsum's own GOTESTSUM_FORMAT knob). -count=1
# defeats Go's test result cache — a test task must actually test. The shared
# timeout is project-overridable from the root Justfile, the home of all project
# customization:
#     export TEST_GO_TIMEOUT := '20m'
#
# A PASSING test's output is not shown by default — neither t.Log nor a direct
# write to os.Stderr — so adding prints to chase a green-here/red-in-CI failure
# looks like the prints never ran. Two independent layers suppress it: `go test`
# discards a passing package's output entirely without -v, and gotestsum (which
# passes -json, so it always HAS the output) hides it in its default format. To
# see it:
#     GOTESTSUM_FORMAT=standard-verbose just do test go
#
# Every recipe resolves CGO_ENABLED through lib.just's `go_cgo`, exactly as the
# build module does, so a project declaring `export GO_CGO := '1'` TESTS the
# artifact it ships. Left to go's own default this would be silently
# environment-dependent — cgo is on for a native build only where a C toolchain
# happens to be installed, so the same tree would test a cgo binary on a machine
# with Xcode and a pure-Go one without it. `race` is the exception and forces 1
# unconditionally: the race detector injects runtime/cgo regardless.

# Unit tests.
unit: (_banner "test go" "unit")
    CGO_ENABLED="{{ go_cgo }}" \
        gotestsum -- -count=1 -timeout "${TEST_GO_TIMEOUT:-10m}" ./...

# Unit tests under the race detector. The final link is delegated to the
# system linker: the race detector injects runtime/cgo into every package, and
# hardened CGO_CFLAGS (-fstack-protector-strong, -fPIE) make those objects
# reference libc symbols Go's internal linker cannot resolve on Linux
# ("relocation target stderr not defined") — see golang/go#52690, #54313,
# #58619. On macOS with Xcode 15+, ld emits "has malformed LC_DYSYMTAB"
# warnings for race builds; cosmetic, the binaries are correct (golang/go#61229).
race: (_banner "test go" "race")
    CGO_ENABLED=1 gotestsum -- -count=1 -timeout "${TEST_GO_TIMEOUT:-10m}" -ldflags=-linkmode=external -race ./...

# Benchmarks, with allocation stats. -run '^$' deselects unit tests so only
# benchmarks run — `just do test go` already covers the tests themselves.
bench: (_banner "test go" "bench")
    CGO_ENABLED="{{ go_cgo }}" \
        go test -count=1 -timeout "${TEST_GO_TIMEOUT:-10m}" -run '^$' -bench . -benchmem ./...

# Fuzz smoke: every Fuzz* target in every package, each for a short budget —
# a regression net, not a campaign. The seed corpus of the target runs first
# (that is what -run selects), then the engine mutates for TEST_GO_FUZZ_TIME
# (default 10s; export from the root Justfile to raise it). Driven by
# `go test -fuzz` itself, never a prebuilt test binary: only the go tool's
# fuzz build compiles in the coverage counters, and without them the engine
# mutates blind. `go test -fuzz` accepts one target per invocation, hence the
# loop; targets are discovered with -list rather than grep so build tags and
# _test.go placement are Go's call, not a regex's.
#
# The verdict comes from the crasher, not the exit code. A real finding always
# writes the failing input under the package's testdata/fuzz/<Target>/ (commit
# it — it is a regression test from then on). But the coordinator can also
# exit 1 with "context deadline exceeded" when a worker is mid-iteration as
# fuzztime expires — a shutdown hiccup, not a finding, and slow targets hit it
# most. So: exit 1 WITH a new testdata file is a failure; exit 1 without one
# is retried once, and a second in a row is treated as real. The generated
# corpus lives under $(go env GOCACHE)/fuzz — cache that between CI runs and
# fuzzing becomes cumulative. A tree with no fuzz targets says so and passes.
fuzz: (_banner "test go" "fuzz")
    #!/usr/bin/env bash
    set -euo pipefail
    export CGO_ENABLED="{{ go_cgo }}"
    fuzztime="${TEST_GO_FUZZ_TIME:-10s}"
    # Crasher count for a target: the directory does not exist until the first
    # finding, and a missing directory is zero, not an error (pipefail).
    crashers() {
        if [ -d "$1" ]; then find "$1" -type f | wc -l; else echo 0; fi
    }
    found=0
    fail=0
    for pkg in $(go list ./...); do
        targets=$(go test -count=1 -run '^$' -list '^Fuzz' "$pkg" | grep '^Fuzz' || true)
        [ -n "$targets" ] || continue
        dir=$(go list -f '{{{{.Dir}}' "$pkg")
        for target in $targets; do
            found=1
            echo "fuzzing $pkg $target for $fuzztime"
            before=$(crashers "$dir/testdata/fuzz/$target")
            ok=0
            for attempt in 1 2; do
                if go test -count=1 -timeout "${TEST_GO_TIMEOUT:-10m}" \
                    -run "^${target}\$" -fuzz "^${target}\$" -fuzztime "$fuzztime" "$pkg"; then
                    ok=1
                    break
                fi
                after=$(crashers "$dir/testdata/fuzz/$target")
                if [ "$after" -gt "$before" ]; then
                    echo "$target: new crasher written under $dir/testdata/fuzz/$target — commit it as a regression test" >&2
                    break
                fi
                echo "$target: exit without a crasher (attempt $attempt) — coordinator shutdown hiccup, retrying" >&2
            done
            if [ "$ok" -eq 1 ]; then
                echo "PASS: $target"
            else
                fail=1
            fi
        done
    done
    if [ "$found" -eq 0 ]; then
        echo "no Fuzz* targets in this module — nothing to fuzz"
    fi
    exit "$fail"

# Coverage: per-function summary, an HTML report under build/coverage/, and an
# optional minimum gate — export TEST_GO_COVER_MIN := '80' (integer percent)
# from the root Justfile to enforce a floor; unset or 0 reports without gating.
cover: (_banner "test go" "cover")
    #!/usr/bin/env bash
    set -euo pipefail
    export CGO_ENABLED="{{ go_cgo }}"
    dir=build/coverage
    mkdir -p "$dir"
    gotestsum -- -count=1 -timeout "${TEST_GO_TIMEOUT:-10m}" -coverprofile="$dir/coverage.out" ./...
    go tool cover -func="$dir/coverage.out"
    go tool cover -html="$dir/coverage.out" -o "$dir/coverage.html"
    echo "HTML report: $dir/coverage.html"
    min="${TEST_GO_COVER_MIN:-0}"
    # Fail CLOSED on a malformed threshold. `[ "$min" -gt 0 ]` errors on a
    # non-integer (a float like 80.0, a typo like 8O), and swallowing that error
    # would silently skip the whole gate — a mistyped minimum must not disable
    # enforcement. Reject anything that is not a whole number, loudly.
    case "$min" in
        ''|*[!0-9]*)
            echo "TEST_GO_COVER_MIN must be a whole-number percentage (got '$min')." >&2
            exit 2
            ;;
    esac
    if [ "$min" -gt 0 ]; then
        total=$(go tool cover -func="$dir/coverage.out" | awk '/^total:/ { gsub(/%/, "", $3); print $3 }')
        if [ "${total%%.*}" -lt "$min" ]; then
            echo "coverage ${total}% is below the ${min}% minimum" >&2
            exit 1
        fi
        echo "coverage ${total}% meets the ${min}% minimum"
    fi

# CPU and memory profiles, one pair per package, with pprof top-20 summaries
# printed and PNG call graphs rendered via the pinned `dot` (goccy/go-graphviz:
# real graphviz compiled to WASM, so it lives in aqua like any Go tool).
# Informational: a package whose tests fail is still profiled past, never
# fails the run. Artifacts land under build/profiles/ (raw) and
# build/profiles-docs/ (PNG); analyze interactively with `go tool pprof`.
profile: (_banner "test go" "profile")
    #!/usr/bin/env bash
    set -euo pipefail
    export CGO_ENABLED="{{ go_cgo }}"
    prof=build/profiles
    docs=build/profiles-docs
    mkdir -p "$prof" "$docs"
    # pprof's own -png shells out to dot writing to a pipe, which the WASM dot
    # cannot do (it needs -o) — so render from pprof's -dot text instead. The
    # pre-create matters: under a sandbox the WASM runtime can overwrite files
    # but not always create them. Paths stay cwd-relative for the same reason
    # (the runtime preopens only the working directory).
    render() {
        src=$1; png=$2; shift 2
        go tool pprof -dot -nodecount=20 "$@" "$src" > "$png.dot" 2>/dev/null
        : > "$png"
        dot -Tpng -o "$png" "$png.dot"
        rm -f "$png.dot"
        echo "  -> $png"
    }
    for pkg in $(go list ./...); do
        # Filename-safe name from the FULL import path, not just the last segment:
        # example/a/client and example/b/client both end in "client" and would
        # otherwise overwrite each other's binary and profiles. '/' -> '__'; the
        # only other char a Go import path carries that matters here is '.', which
        # is already filename-safe.
        name=${pkg//\//__}
        echo "Profiling $pkg..."
        go test -count=1 -o "$prof/$name.test" "$pkg" \
            -cpuprofile "$prof/${name}_cpu.prof" \
            -memprofile "$prof/${name}_mem.prof" || true
        if [ -s "$prof/${name}_cpu.prof" ]; then
            echo "  CPU profile (top 20):"
            go tool pprof -top -nodecount=20 "$prof/${name}_cpu.prof" 2>/dev/null || true
            render "$prof/${name}_cpu.prof" "$docs/${name}_cpu.png"
        fi
        if [ -s "$prof/${name}_mem.prof" ]; then
            echo "  Memory profile — alloc_space (top 20):"
            go tool pprof -top -nodecount=20 -alloc_space "$prof/${name}_mem.prof" 2>/dev/null || true
            render "$prof/${name}_mem.prof" "$docs/${name}_alloc.png" -alloc_space
        fi
    done
    echo "Profiles written to $prof/, diagrams to $docs/"
