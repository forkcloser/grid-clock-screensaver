# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# xcodebuild and clang come from the system toolchain — aqua cannot pin Xcode.

XCODE_PROJECT := 'Grid Clock.xcodeproj'
XCODE_SCHEME := 'Grid Clock'
SAVER := 'Grid Clock.saver'
# Upstream's namespace, deliberately: it is the preferences domain, so a 0.0.5
# user's settings carry over. verify-bundle holds the build to it.
BUNDLE_ID := 'com.chrstphrknwtn.grid-clock'
# What a bundle built outside a release says it is. The project file pins the
# same value; only `just build <config> <version>` (which the release calls
# with the tag) produces anything else.
DEV_VERSION := '0.0.0'

# The FIRST recipe defined here becomes `just`'s default.
lint: do::lint::default
fix: do::fix::default
test: test-parity test-runtime test-bundle verify-bundle

# -destination generic/platform=macOS keeps the build independent of the host
# machine. The version is an argument, not a project setting: the release
# passes the tag, everything else gets DEV_VERSION. CFBundleVersion must be an
# integer that only grows; the commit count is one, so a shallow clone (which
# would undercount) is refused rather than shipped.
[doc('Build the .saver bundle (configuration: Release or Debug; version: what the bundle claims to be)')]
build configuration='Release' version=DEV_VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        echo "shallow clone: the build number is the commit count and would be wrong — fetch the full history first" >&2
        exit 1
    fi
    build_number=$(git rev-list --count HEAD)
    xcodebuild -project '{{ XCODE_PROJECT }}' -scheme '{{ XCODE_SCHEME }}' \
        -configuration '{{ configuration }}' -destination 'generic/platform=macOS' \
        -derivedDataPath build \
        MARKETING_VERSION='{{ version }}' CURRENT_PROJECT_VERSION="$build_number" \
        build
    echo "built build/Build/Products/{{ configuration }}/{{ SAVER }} ({{ version }}, build $build_number)"

# What the shipped bundle must be, asserted rather than inspected — v0.1.0 went
# out as a universal binary claiming to be 1.0.0 (1), and nothing noticed. Runs
# on every `just test` against the dev build and, from the goreleaser hooks,
# against the tagged one.
[doc('Assert the built .saver is what we ship: version, bundle id, arch, min OS, signature')]
verify-bundle version=DEV_VERSION configuration='Release': (build configuration version)
    #!/usr/bin/env bash
    set -euo pipefail
    saver='build/Build/Products/{{ configuration }}/{{ SAVER }}'
    plist="$saver/Contents/Info.plist"
    binary="$saver/Contents/MacOS/Grid Clock"
    fail() { echo "verify-bundle: $*" >&2; exit 1; }
    expect() {
        actual=$(plutil -extract "$1" raw -o - "$plist")
        [ "$actual" = "$2" ] || fail "$1 is '$actual', expected '$2'"
        echo "  $1 = $actual"
    }
    expect CFBundleShortVersionString '{{ version }}'
    expect CFBundleIdentifier '{{ BUNDLE_ID }}'
    expect LSMinimumSystemVersion 14.0
    expect NSPrincipalClass GridClock
    build_number=$(plutil -extract CFBundleVersion raw -o - "$plist")
    [[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "CFBundleVersion is '$build_number', expected a positive integer"
    echo "  CFBundleVersion = $build_number"
    archs=$(lipo -archs "$binary")
    [ "$archs" = "arm64" ] || fail "binary architectures are '$archs', expected exactly arm64"
    echo "  archs = $archs"
    codesign --verify --deep --strict "$saver" || fail "the code signature does not verify"
    flags=$(codesign -d --verbose=1 "$saver" 2>&1 | sed -n 's/^CodeDirectory.*flags=\([^ ]*\).*/\1/p')
    case "$flags" in
        *runtime*) ;;
        *) fail "hardened runtime flag missing (flags=$flags)" ;;
    esac
    echo "  codesign = valid, flags=$flags"
    echo "verify-bundle: {{ SAVER }} is {{ version }}, arm64, macOS 14.0+, hardened ad-hoc signature intact"

# GridClock.m is compiled into the harness directly: the shipped source is what
# is tested, not a copy of its logic. test/regenerate-golden.js produces the
# golden file.
[doc('Parity test: every minute of the day against upstream 0.0.5')]
test-parity:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror \
        -framework Cocoa -framework CoreText -framework ScreenSaver \
        -o build/test/parity test/parity.m
    build/test/parity > build/test/parity.txt
    if ! diff -u test/golden.txt build/test/parity.txt > build/test/parity.diff; then
        echo "the clock disagrees with upstream — first differing minutes:" >&2
        head -20 build/test/parity.diff >&2
        exit 1
    fi
    echo "parity: 1440/1440 minutes and the letter grid match upstream 0.0.5"

# Process behaviour the parity test cannot see: the timer sleeps between
# transitions instead of spinning at 30 Hz, and a time-zone change is read at
# the next minute. GridClock.m is compiled in directly, as for parity.
[doc('Runtime test: timer cadence and time-zone pickup')]
test-runtime:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror \
        -framework Cocoa -framework CoreText -framework ScreenSaver \
        -o build/test/runtime test/runtime.m
    build/test/runtime

[doc('Bundle test: load the built .saver and render a frame')]
test-bundle configuration='Release': (build configuration DEV_VERSION)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror \
        -framework Cocoa -framework ScreenSaver \
        -o build/test/load test/load.m
    build/test/load "build/Build/Products/{{ configuration }}/{{ SAVER }}" build/test/render.png

# System Settings reads the screensaver list once at launch: quit it (⌘Q) first
# or the saver will not appear.
[doc('Install the built .saver into ~/Library/Screen Savers')]
install configuration='Release': (build configuration DEV_VERSION)
    #!/usr/bin/env bash
    set -euo pipefail
    dest="$HOME/Library/Screen Savers"
    mkdir -p "$dest"
    rm -rf "$dest/{{ SAVER }}"
    cp -R "build/Build/Products/{{ configuration }}/{{ SAVER }}" "$dest/"
    echo "installed $dest/{{ SAVER }} — quit System Settings (⌘Q) and reopen if it is running"

# Preferences are per-host and are left behind on purpose; the readme documents
# clearing them.
[doc('Remove the .saver from ~/Library/Screen Savers')]
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "$HOME/Library/Screen Savers/{{ SAVER }}"
    echo "removed"
