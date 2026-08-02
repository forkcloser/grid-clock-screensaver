# Grid Clock

A word clock screensaver for macOS. The face is a 16 × 15 grid of letters; the
lit ones read out the time.

![Grid Clock Screenshot](GridClock.png)

## About this fork

This is a fork of [chrstphrknwtn/grid-clock-screensaver](https://github.com/chrstphrknwtn/grid-clock-screensaver),
ported to modern macOS.

Upstream (0.0.5, 2018) drew the clock as a local HTML page inside a `WebView` —
WebKit 1. That stopped working on macOS 14, which moved screensavers into the
sandboxed `legacyScreenSaver` host. The WebKit 1 API itself is not the problem:
it is still in the macOS 26 SDK, still links, and still renders the original
page correctly inside an ordinary app. It is the sandboxed screensaver host that
it no longer draws in.

So rather than swap in `WKWebView` and stay exposed to the same class of
problem, this fork replaces the web view with a native Core Text renderer. The
bundle now loads nothing at runtime — no HTML, no JavaScript, no web engine, no
file access.

The clock itself is unchanged. The port is checked against upstream's
`index.js` for all 1440 minutes of the day, and uses the same `#222` / `#fff`
colours and the same 400 ms crossfade.

## Requirements

macOS 14 (Sonoma) or later — the same set Apple still issues security updates
for. That floor is deliberate rather than technical: nothing here needs a modern
API, but macOS 14 is exactly where upstream broke, so on macOS 13 and earlier
you may as well run [the original](https://github.com/chrstphrknwtn/grid-clock-screensaver),
which works fine there.

Building needs Xcode. Verified on macOS 26.6 (Tahoe) with Xcode 26.6; 14 and 15
are declared but untested.

## Install

There is no prebuilt download for this fork — build it from source.

### 1. Build

```sh
git clone https://github.com/forkcloser/grid-clock-screensaver.git
cd grid-clock-screensaver

xcodebuild -project 'Grid Clock.xcodeproj' -scheme 'Grid Clock' \
           -configuration Release -destination 'generic/platform=macOS' \
           -derivedDataPath build build
```

`-destination 'generic/platform=macOS'` is what produces a universal
(arm64 + x86_64) binary. Without it you get one for your own architecture only.

### 2. Copy it into place

Quit System Settings first (⌘Q — closing the window is not enough; it reads the
screensaver list once at launch).

```sh
cp -R build/Build/Products/Release/'Grid Clock.saver' ~/Library/'Screen Savers'/
```

`~/Library/Screen Savers` installs for your user only, and the folder may not
exist yet — `mkdir -p` it if the copy fails. Use `/Library/Screen Savers`
(needs `sudo`) to install for everyone.

The bundle is ad-hoc signed with the hardened runtime enabled, so it loads
locally without a developer account and is ready to be re-signed and notarised
as-is. A copy moved between machines over the internet also needs to clear
quarantine (`xattr -dr com.apple.quarantine 'Grid Clock.saver'`), or to be
properly signed and notarised.

`legacyScreenSaver` carries `com.apple.security.cs.disable-library-validation`,
which is why an ad-hoc signed plug-in loads into it at all.

### 3. Select it

**macOS 26 (Tahoe)** folded Screen Saver into the Wallpaper pane — there is no
longer a Screen Saver item in the System Settings sidebar:

1. System Settings → **Wallpaper**
2. Click **Screen Saver…** at the top right, next to *Clock Appearance…*
3. Scroll to the bottom. Grid Clock is in the last section, alongside
   **Message** — the two are shown by the same mechanism. Its thumbnail is
   near-black, so it is easy to skim past.

On **macOS 14 and 15**, Screen Saver is its own sidebar item instead; the saver
appears at the bottom of that list, under *Other*.

If it is not listed at all, you almost certainly installed it while System
Settings was running. Quit with ⌘Q and reopen.

## Options

With Grid Clock selected, **Options…** appears below the preview:

| Setting | Effect |
| --- | --- |
| Main display only *(default)* | Clock on the main display, other displays black |
| All displays | Clock on every display |

## Uninstall

```sh
rm -rf ~/Library/'Screen Savers'/'Grid Clock.saver'
```

Preferences are stored per-host and are left behind. To clear them too:

```sh
defaults -currentHost delete com.chrstphrknwtn.grid-clock
rm -f ~/Library/Preferences/ByHost/com.chrstphrknwtn.grid-clock.*.plist
```

The second line is not redundant — `defaults delete` empties the file but leaves
it on disk.

## How it works

Every word the clock can say is a run of consecutive cells in the grid, so
`GridClock.m` is a letter table, a table of `(offset, length)` spans, and the
rules that pick which spans to light for a given hour and minute.

Drawing is Core Text. A cell is only ever unlit, lighting up, going dark, or
lit, and they all turn over on the same minute boundary — so a frame is at most
four `CTFontDrawGlyphs` calls, one per colour. Nothing is redrawn between
transitions.

Type is the system font at a size proportional to the grid cell, so the face
scales cleanly from the System Settings thumbnail up to a 6K display.

## Differences from upstream

Behaviour is otherwise identical to 0.0.5.

- **Font sizing.** Upstream sized type in viewport units and carried a media
  query specifically to stop the System Settings thumbnail from breaking.
  Sizing off the cell handles that case, so both are gone.
- **Display options.** "Last focused screen" has been dropped. macOS 14 and
  later run a separate saver process per display, which leaves nothing coherent
  for it to mean. An existing *all screens* preference migrates across; *last
  focused* becomes *main display only*.
- **Removed.** `Webview/` and `ConfigureSheet.xib`. The options sheet is built
  in code — the xib was loaded with `+[NSBundle loadNibNamed:owner:]`,
  deprecated since macOS 10.8.
- **Project file rebuilt.** Modern object version, current warning set (the
  build is warning-clean under it), separate Debug and Release settings that
  actually differ, universal `ARCHS`, hardened runtime, and a checked-in shared
  scheme so `xcodebuild -scheme` works straight from a clone. `Info.plist` is
  gone — it is generated from build settings now.

## Related

- [Epoch Flip Clock Screensaver](https://github.com/chrstphrknwtn/epoch-flip-clock-screensaver)
- [Word Clock Screensaver](https://github.com/chrstphrknwtn/word-clock-screensaver)
