# This file is the project's own.
# Add recipes leveraging provided `do` ready-made recipes, or create your own.
# The import must be kept: it mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# This project builds with Xcode, which aqua cannot pin — `xcodebuild` and
# `clang` come from the system toolchain (the same eyes-open exception
# book/recipes.md makes for languages whose toolchain lives outside aqua).
# Everything else these recipes touch is pinned as usual. The floor is macOS 14
# and an Xcode carrying a macOS SDK; verified on macOS 26.6 with Xcode 26.6.

XCODE_PROJECT := 'Grid Clock.xcodeproj'
XCODE_SCHEME := 'Grid Clock'
SAVER := 'Grid Clock.saver'

# The FIRST recipe defined here becomes `just`'s default.
lint: do::lint::default
fix: do::fix::default
test: test-parity test-bundle

# Build the screensaver bundle. Release by default; `just build Debug` for the
# debug configuration. Universal (arm64 + x86_64): the generic macOS
# destination is what makes it so — without it xcodebuild builds for this
# machine's architecture only.
[doc('Build the .saver bundle (configuration: Release or Debug)')]
build configuration='Release':
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -project '{{ XCODE_PROJECT }}' -scheme '{{ XCODE_SCHEME }}' \
        -configuration '{{ configuration }}' -destination 'generic/platform=macOS' \
        -derivedDataPath build build
    echo "built build/Build/Products/{{ configuration }}/{{ SAVER }}"

# The port must say exactly what upstream 0.0.5 said, for all 1440 minutes.
# GridClock.m is compiled into the harness directly, so what is tested is the
# shipped source and not a copy of its logic. test/regenerate-golden.js is
# where the golden file comes from.
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

# What a source-level test cannot check: that the artifact we ship is a
# loadable bundle whose principal class is wired up and actually draws. Depends
# on the build, so the recipe stands alone.
[doc('Bundle test: load the built .saver and render a frame')]
test-bundle configuration='Release': (build configuration)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    clang -fobjc-arc -O0 -Werror \
        -framework Cocoa -framework ScreenSaver \
        -o build/test/load test/load.m
    build/test/load "build/Build/Products/{{ configuration }}/{{ SAVER }}" build/test/render.png

# Install into this user's screensaver directory. System Settings reads the
# screensaver list once at launch, so it must be quit (⌘Q) first or the saver
# will not appear.
[doc('Install the built .saver into ~/Library/Screen Savers')]
install configuration='Release': (build configuration)
    #!/usr/bin/env bash
    set -euo pipefail
    dest="$HOME/Library/Screen Savers"
    mkdir -p "$dest"
    rm -rf "$dest/{{ SAVER }}"
    cp -R "build/Build/Products/{{ configuration }}/{{ SAVER }}" "$dest/"
    echo "installed $dest/{{ SAVER }} — quit System Settings (⌘Q) and reopen if it is running"

# Remove the installed saver. Preferences are per-host and are left behind on
# purpose; the readme documents how to clear them too.
[doc('Remove the .saver from ~/Library/Screen Savers')]
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "$HOME/Library/Screen Savers/{{ SAVER }}"
    echo "removed"
