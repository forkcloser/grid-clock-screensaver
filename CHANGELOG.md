# Changelog

Notable changes, written by hand before the release that carries them. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the
versions [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The release
pipeline refuses to cut a version that has no section here
(`scripts/release-notes.sh`).

## [Unreleased]

### Changed

- The installer reads the archive's name from the release's own signed
  `checksums.txt` instead of guessing it, so it can no longer disagree with the
  release it installs — v0.1.0 shipped `grid-clock_0.1.0_universal.zip` while
  the installer on `main` looked for `…_arm64.zip` and failed. It accepts a
  universal archive (v0.1.0) as well as the arm64-only one. `--version` takes
  `1.0.0` as well as `v1.0.0`. The readme's one-liner runs the release's own
  installer rather than `main`'s.
- The bundle's version follows the tag: `CFBundleShortVersionString` is the
  release version and `CFBundleVersion` the commit count. The project file pins
  `0.0.0`, so a build made outside `just build <config> <version>` is
  recognisably unversioned. v0.1.0 claimed to be 1.0.0 (1).
- Settled, the saver's timer sleeps until the next minute instead of waking 30
  times a second; the 30 Hz cadence is used for the 400 ms crossfade only.
- A system time-zone change is seen at the next minute rather than after a
  restart.
- Bundle metadata names the port's copyright holder and licence (Forkcloser,
  MIT) and credits the clock's design to Christopher Newton, matching `LICENSE`
  and the readme. It carried upstream's 2018 copyright line.
- The readme's screenshot is a frame rendered by this build, not upstream's
  2016 WebView render.
- Releases carry hand-written notes (this file) instead of goreleaser's commit
  list.

### Added

- `just verify-bundle`: asserts the built bundle's version, bundle identifier,
  arm64-only binary, minimum macOS 14.0, and an intact ad-hoc signature with the
  hardened runtime flag. Run by `just test` and by the release before packaging.
- `just test-runtime`: timer cadence and time-zone pickup.

### Fixed

- Two pointers at the repository's issue tracker, which is disabled: the
  licensing section now names the upstream thread this fork opened, and the
  installer's verification-failure message names the private reporting channel.

## [0.1.0] - 2026-08-03

### Added

- Port of [chrstphrknwtn/grid-clock-screensaver](https://github.com/chrstphrknwtn/grid-clock-screensaver)
  0.0.5 to macOS 14 and later: a native Core Text renderer in place of the
  WebKit 1 `WebView` that the sandboxed screensaver host no longer draws, an
  options sheet built in code, a parity test against upstream's `index.js` for
  all 1440 minutes, keyless-signed releases, and a verifying installer.
