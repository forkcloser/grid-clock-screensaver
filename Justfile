# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# xcodebuild and clang come from the system toolchain — aqua cannot pin Xcode.

XCODE_PROJECT := 'Grid Clock.xcodeproj'
XCODE_SCHEME := 'Grid Clock'
SAVER := 'Grid Clock.saver'

# The FIRST recipe defined here becomes `just`'s default.
lint: do::lint::default
fix: do::fix::default
test: test-parity test-bundle

# -destination generic/platform=macOS keeps the build independent of the host
# machine. Twin of the goreleaser before-hook — change both.
[doc('Build the .saver bundle (configuration: Release or Debug)')]
build configuration='Release':
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -project '{{ XCODE_PROJECT }}' -scheme '{{ XCODE_SCHEME }}' \
        -configuration '{{ configuration }}' -destination 'generic/platform=macOS' \
        -derivedDataPath build build
    echo "built build/Build/Products/{{ configuration }}/{{ SAVER }}"

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

[doc('Bundle test: load the built .saver and render a frame')]
test-bundle configuration='Release': (build configuration)
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
install configuration='Release': (build configuration)
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
