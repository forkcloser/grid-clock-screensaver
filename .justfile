# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# xcodebuild and clang come from the system toolchain — aqua cannot pin Xcode.

XCODE_PROJECT := 'Grid Clock.xcodeproj'
XCODE_SCHEME := 'Grid Clock'
SAVER := 'Grid Clock.saver'
# Ours since 1.1 (1.0 shipped as world.farcloser.grid-clock, 0.1.0 under
# upstream's com.chrstphrknwtn.grid-clock). It is also the preferences domain;
# GridClock.m reads the old ones once on first launch. verify-bundle holds the
# build to it.
BUNDLE_ID := 'org.forkcloser.grid-clock'
# What a bundle built outside a release says it is. The project file pins the
# same value; only `just build <config> <version>` (which the release calls
# with the tag) produces anything else.
DEV_VERSION := '0.0.0'

# The FIRST recipe defined here becomes `just`'s default.
lint: do::lint::default
fix: do::fix::default
# The security workflow runs `just security`.
security: do::security::default
test: test-parity test-runtime test-bundle verify-bundle

# -destination generic/platform=macOS keeps the build independent of the host
# machine. The version is an argument, not a project setting: the release
# passes the tag, everything else gets DEV_VERSION. CFBundleVersion must be an
# integer that only grows; the commit count is one, so a shallow clone (which
# would undercount) is refused rather than shipped. The signature is ad hoc
# (the project's "-") unless GRID_CLOCK_SIGN_IDENTITY names an identity, the
# release workflow's Developer ID Application; that one is timestamped, as
# notarization requires, and signed under GRID_CLOCK_SIGN_TEAM, the team
# manual signing asks for beside the identity (the project pins none).
[doc('Build the .saver bundle (configuration: Release or Debug; version: what the bundle claims to be)')]
build configuration='Release' version=DEV_VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        echo "shallow clone: the build number is the commit count and would be wrong — fetch the full history first" >&2
        exit 1
    fi
    build_number=$(git rev-list --count HEAD)
    identity="${GRID_CLOCK_SIGN_IDENTITY:--}"
    flags=""
    team=""
    if [ "$identity" != "-" ]; then
        flags="--timestamp"
        team="${GRID_CLOCK_SIGN_TEAM:?GRID_CLOCK_SIGN_TEAM is unset: a signing identity needs its team}"
    fi
    xcodebuild -project '{{ XCODE_PROJECT }}' -scheme '{{ XCODE_SCHEME }}' \
        -configuration '{{ configuration }}' -destination 'generic/platform=macOS' \
        -derivedDataPath build \
        MARKETING_VERSION='{{ version }}' CURRENT_PROJECT_VERSION="$build_number" \
        CODE_SIGN_IDENTITY="$identity" OTHER_CODE_SIGN_FLAGS="$flags" DEVELOPMENT_TEAM="$team" \
        build
    echo "built build/Build/Products/{{ configuration }}/{{ SAVER }} ({{ version }}, build $build_number, signed by $identity)"

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
    expect LSMinimumSystemVersion 15.0
    expect NSPrincipalClass GridClock
    build_number=$(plutil -extract CFBundleVersion raw -o - "$plist")
    [[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "CFBundleVersion is '$build_number', expected a positive integer"
    echo "  CFBundleVersion = $build_number"
    archs=$(lipo -archs "$binary")
    [ "$archs" = "arm64" ] || fail "binary architectures are '$archs', expected exactly arm64"
    echo "  archs = $archs"
    codesign --verify --deep --strict "$saver" || fail "the code signature does not verify"
    details=$(codesign -d --verbose=2 "$saver" 2>&1)
    flags=$(printf '%s\n' "$details" | sed -n 's/^CodeDirectory.*flags=\([^ ]*\).*/\1/p')
    case "$flags" in
        *runtime*) ;;
        *) fail "hardened runtime flag missing (flags=$flags)" ;;
    esac
    echo "  codesign = valid, flags=$flags"
    # The release signs with the Developer ID identity the workflow imports;
    # the signature must then be that identity's, timestamped. Anything else
    # is ad hoc, which a local build is.
    if [ -n "${GRID_CLOCK_SIGN_IDENTITY:-}" ]; then
        printf '%s\n' "$details" | grep -q '^Authority=Developer ID Application' || fail "signed, but not by the Developer ID Application identity"
        printf '%s\n' "$details" | grep -q '^Timestamp=' || fail "the Developer ID signature carries no timestamp"
        echo "  signature = Developer ID Application, timestamped"
        echo "verify-bundle: {{ SAVER }} is {{ version }}, arm64, macOS 15.0+, hardened Developer ID signature intact"
    else
        echo "verify-bundle: {{ SAVER }} is {{ version }}, arm64, macOS 15.0+, hardened ad-hoc signature intact"
    fi

# A bundle a human installs through System Settings is evaluated by
# Gatekeeper, which accepts a Developer ID signature only once Apple has
# notarized it; the ticket is stapled so the check needs no network. Without
# an identity (a local build or dry run) there is nothing to notarize and the
# recipe says so; with one and no credentials it fails, since a Developer ID
# build that leaves here unnotarized would be refused on every install. The
# verdict is notarytool's own "status: Accepted": --wait's exit status is not
# it, and spctl has no assessment for a plug-in (its execute type answers for
# app bundles alone).
[doc('Notarize the signed .saver with notarytool and staple the ticket (release only)')]
notarize version=DEV_VERSION configuration='Release':
    #!/usr/bin/env bash
    set -euo pipefail
    saver='build/Build/Products/{{ configuration }}/{{ SAVER }}'
    if [ -z "${GRID_CLOCK_SIGN_IDENTITY:-}" ]; then
        echo "notarize: no signing identity, the bundle is ad hoc signed — nothing to notarize"
        exit 0
    fi
    for v in GRID_CLOCK_NOTARY_KEY GRID_CLOCK_NOTARY_KEY_ID GRID_CLOCK_NOTARY_ISSUER_ID; do
        [ -n "${!v:-}" ] || { echo "notarize: $v is not set; a Developer ID build must be notarized" >&2; exit 1; }
    done
    mkdir -p build/notarize
    archive='build/notarize/{{ SAVER }}.zip'
    rm -f "$archive"
    ditto -c -k --sequesterRsrc --keepParent "$saver" "$archive"
    key=(--key "${GRID_CLOCK_NOTARY_KEY:?}" --key-id "${GRID_CLOCK_NOTARY_KEY_ID:?}" --issuer "${GRID_CLOCK_NOTARY_ISSUER_ID:?}")
    submission=$(xcrun notarytool submit "$archive" --wait "${key[@]}" 2>&1 | tee /dev/stderr) || true
    id=$(printf '%s\n' "$submission" | sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' | head -n 1)
    if ! printf '%s\n' "$submission" | grep -q '^ *status: Accepted$'; then
        echo "notarize: Apple did not accept the submission${id:+ $id}" >&2
        [ -z "$id" ] || xcrun notarytool log "$id" "${key[@]}" >&2 || true
        exit 1
    fi
    xcrun stapler staple "$saver"
    xcrun stapler validate "$saver"
    echo "notarize: {{ SAVER }} {{ version }} notarized (submission ${id:-?}), ticket stapled"

# GridClock.m is compiled into the harness directly: the shipped source is what
# is tested, not a copy of its logic. test/regenerate-golden.js produces the
# golden file.
[doc('Parity test: every minute of the day against upstream 0.0.5')]
test-parity:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror -Wconversion \
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
    clang -fobjc-arc -O0 -Werror -Wconversion \
        -framework Cocoa -framework CoreText -framework ScreenSaver \
        -o build/test/runtime test/runtime.m
    build/test/runtime

[doc('Bundle test: load the built .saver and render a frame')]
test-bundle configuration='Release': (build configuration DEV_VERSION)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror -Wconversion \
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
    ditto "build/Build/Products/{{ configuration }}/{{ SAVER }}" "$dest/{{ SAVER }}"
    echo "installed $dest/{{ SAVER }} — quit System Settings (⌘Q) and reopen if it is running"

# Preferences are per-host and are left behind on purpose; the readme documents
# clearing them.
[doc('Remove the .saver from ~/Library/Screen Savers')]
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "$HOME/Library/Screen Savers/{{ SAVER }}"
    echo "removed"
