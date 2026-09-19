# Development

## Why a native port

Upstream (0.0.5, 2018) rendered the clock as a local HTML page in a WebKit 1
`WebView`. macOS 14 moved screensavers into the sandboxed `legacyScreenSaver`
host, where that view no longer draws; the API itself still exists and still
renders inside an ordinary app. Rather than move to `WKWebView` and stay
exposed to the same class of breakage, this fork draws the clock with Core
Text. No HTML, JavaScript, web engine or file access at runtime.

The minimum is macOS 14 because that is where upstream broke; on macOS 13 and
earlier the original works. macOS 14 is the declared minimum but is not
exercised by CI, which runs on macOS 15.

## How it works

Every word the clock can say is a run of consecutive cells in the grid, so
`GridClock.m` is a letter table, a table of `(offset, length)` spans, and the
rules that pick which spans to light for a given hour and minute.

A cell is unlit, lighting up, going dark, or lit, and all cells turn over on
the same minute boundary, so a frame is at most four `CTFontDrawGlyphs` calls,
one per colour. Nothing is redrawn between transitions. Type is the system font
at a size proportional to the grid cell, so the face scales from the System
Settings thumbnail to a 6K display.

## Differences from upstream

- **Brightness option.** 5–100 %, a multiplier on the two grey levels. The
  idea is from [chrstphrknwtn/grid-clock-screensaver#16](https://github.com/chrstphrknwtn/grid-clock-screensaver/pull/16),
  done there as CSS opacity.
- **Font sizing** off the cell, replacing upstream's viewport units and the
  media query that protected the System Settings thumbnail.
- **Display options.** "Last focused screen" dropped: macOS 14 and later run
  one saver process per display, so it has no coherent meaning. An existing
  *all screens* preference migrates; *last focused* becomes *main display
  only*. Preferences moved from `com.chrstphrknwtn.grid-clock` to
  `world.farcloser.grid-clock`; 1.0 copies the display setting across on first
  launch.
- **Removed:** `Webview/` and `ConfigureSheet.xib` (the sheet is built in
  code; the xib used `+[NSBundle loadNibNamed:owner:]`, deprecated since
  10.8).
- **Project file rebuilt:** modern object version, warning-clean under the
  current warning set, distinct Debug and Release settings, arm64-only, hardened
  runtime, a checked-in shared scheme, `Info.plist` generated from build
  settings.

### Stacked displays

On macOS 14 and later, `legacyScreenSaver` hands a display arranged above or
below the main one a window whose origin is in CoreGraphics coordinates (y
down) while AppKit reads it as y-up. The window lands off-screen, the saver
never learns which display it is on, and that display shows the system
background. Side-by-side displays have origin y = 0 either way and are
unaffected. The window belongs to the host process and `setFrame:` is ignored,
so no saver can work around it. Documented first in
[chrstphrknwtn/grid-clock-screensaver#16](https://github.com/chrstphrknwtn/grid-clock-screensaver/pull/16).

## Tooling

The repository follows [limen](https://github.com/farcloser/limen): every tool
except Xcode is pinned in `aqua.yaml` and checksum-verified, and the commands
are the ones CI runs.

```sh
just            # lint
just test       # parity, runtime and bundle tests
just build      # the .saver, into build/Build/Products/Release/
just install    # build and copy into ~/Library/Screen Savers
just --list     # everything else
```

`xcodebuild` and `clang` come from the system toolchain, which aqua cannot
pin. Without `just`:

```sh
xcodebuild -project 'Grid Clock.xcodeproj' -scheme 'Grid Clock' \
           -configuration Release -destination 'generic/platform=macOS' \
           -derivedDataPath build build
```

A bundle built this way reports version `0.0.0`; only a release passes a real
one (`just build Release 1.2.3`).

## Tests

- `just test-parity` compiles `GridClock.m` into a harness and checks every
  minute of the day against `test/golden.txt`, generated from upstream 0.0.5's
  `Webview/index.js` by `test/regenerate-golden.js`, which reads that file out
  of git history.
- `just test-runtime` checks that a system time-zone change is read at the
  next minute, and that the timer sleeps between transitions instead of
  spinning at 30 Hz.
- `just test-bundle` builds the `.saver`, loads it the way the host does
  (`NSBundle` → `principalClass`), renders a frame offscreen, and checks it
  looks like a lit grid on black.
- `just verify-bundle` asserts what the built bundle is: version, bundle
  identifier, arm64 only, macOS 14.0 minimum, an intact ad-hoc signature with
  the hardened runtime. The release runs it before packaging.

## Installer verification

The bundle is ad-hoc signed; there is no Apple Developer ID. macOS loads an
ad-hoc signed plug-in into `legacyScreenSaver` (it carries
`com.apple.security.cs.disable-library-validation`), but Gatekeeper refuses to
run it while it carries the quarantine attribute a download gets. The installer
clears that attribute only after establishing trust:

1. **cosign** verifies `checksums.txt` against the release workflow's keyless
   signature: the identity is this repository's `release.yaml` at a `v*` tag,
   certified by Fulcio and recorded in Rekor. No key exists to be stolen.
2. The bundle's SHA-256 is checked against that file.
3. The archive is expanded, de-quarantined, installed, and the bundle's own
   code signature re-verified.

Without cosign the script stops; `--allow-unverified` opts into a checksum-only
install explicitly. The install one-liner fetches the installer attached to the
latest release, not the copy on `main`, and reads the archive name from the
signed `checksums.txt`, so `--version` works for older releases too.

The script cannot verify itself before it runs. It is a release asset listed
in `checksums.txt`, so to check everything by hand first:

```sh
cosign verify-blob --bundle checksums.txt.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    'https://github.com/forkcloser/grid-clock-screensaver/\.github/workflows/release\.yaml@refs/tags/v.*' \
  checksums.txt
shasum -a 256 -c checksums.txt   # the archive and install.sh
```

## Releases

`just do release vX.Y.Z` verifies a clean tree, creates a signed tag and pushes
it. The tag push triggers the release workflow: build on a macOS runner with
the tag as the bundle's version, `verify-bundle`, keyless cosign signature on
`checksums.txt`, GitHub release. Release notes are the version's section in
[`CHANGELOG.md`](./CHANGELOG.md), written beforehand; a version without one
does not release. Pushing `v*` tags is restricted by a repository ruleset.
