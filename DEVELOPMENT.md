# Development

## Why a native port

Upstream (0.0.5, 2018) rendered the clock as a local HTML page in a WebKit 1
`WebView`. macOS 14 moved screensavers into the sandboxed `legacyScreenSaver`
host, where that view no longer draws; the API itself still exists and still
renders inside an ordinary app. Rather than move to `WKWebView` and stay
exposed to the same class of breakage, this fork draws the clock with Core
Text. No HTML, JavaScript, web engine or file access at runtime.

The minimum is macOS 15, the oldest release Apple supports; CI runs on it.

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

What the fork changes for a user, the native rendering, the brightness option,
the display options and the bundle identifier, is the table in
[`UPSTREAM.md`](./UPSTREAM.md). What changed in the project itself:

- **Removed:** `Webview/` and `ConfigureSheet.xib` (the sheet is built in
  code; the xib used `+[NSBundle loadNibNamed:owner:]`, deprecated since
  10.8).
- **Project file rebuilt:** modern object version, warnings are errors under
  the current warning set, distinct Debug and Release settings, arm64-only, hardened
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
except Xcode is pinned in `.hermetic/hermetic.yaml` and checksum-verified, and
the commands are the ones CI runs.

```sh
just            # lint
just test       # parity, runtime and bundle tests
just build      # the .saver, into build/Build/Products/Release/
just install    # build and copy into ~/Library/Screen Savers
just --list     # everything else
```

`xcodebuild` and `clang` come from the system toolchain, which hermetic
cannot pin. Without `just`:

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
  identifier, arm64 only, macOS 15.0 minimum, an intact ad-hoc signature with
  the hardened runtime. The release runs it before packaging.

## Installer verification

A released bundle is signed with Forkcloser's Developer ID Application
identity, hardened runtime and timestamp, notarized by Apple and stapled with
its ticket, as the signing and provenance policy asks of a bundle a human
installs through System Settings (limen's `book/releasing.md`). Gatekeeper
therefore accepts a downloaded release as it accepts any notarized app, and
nothing strips the quarantine attribute. A local build is ad hoc signed and
loads from `~/Library/Screen Savers` without going through Gatekeeper. The
installer establishes trust in this order:

1. **cosign** verifies `checksums.txt` against the release workflow's keyless
   signature: the identity is this repository's `release.yaml` at a `v*` tag,
   certified by Fulcio and recorded in Rekor. No key exists to be stolen.
2. The bundle's SHA-256 is checked against that file.
3. The archive is expanded, the bundle's code signature verified, its
   signing chain required to be Apple's Developer ID one, and the stapled
   notarization ticket required to be present, before it is installed.
   (`spctl` assesses app bundles alone; Gatekeeper evaluates the plug-in
   itself when System Settings loads it.)

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
it. The tag push triggers the release workflow: the Developer ID certificate
is imported into a keychain made for the job and its team id read off the
identity's name, the bundle is built on a macOS runner with the tag as its
version and signed with that identity under that team,
`verify-bundle` asserts the signature is the identity's and timestamped,
`notarize` submits the bundle with `notarytool` and staples the ticket, then
the keyless cosign signature on `checksums.txt`, the GitHub release, whose
notes GitHub writes from the pull requests merged since the previous tag, and
the build provenance attestation over every asset. Pushing `v*` tags is
restricted by a repository ruleset.

The workflow reads five repository secrets, created by the owner and never
seen by a session: `APPLE_DEVELOPER_ID_P12` and
`APPLE_DEVELOPER_ID_P12_PASSWORD` (the certificate, base64, and its password,
the same two taciturn's release uses), and for notarization
`APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` and `APPLE_NOTARY_KEY` (an App
Store Connect API key: its id, the issuer id, and the `.p8` base64). A tag
pushed without them fails before anything builds. A local
`just do release --local --dry-run` has no identity: it builds ad hoc, skips
notarization and says so.
