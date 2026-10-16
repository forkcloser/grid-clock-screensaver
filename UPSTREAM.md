# Upstream

Fork of <https://github.com/chrstphrknwtn/grid-clock-screensaver> (`master`).

- Forked from: [`e1f0f16`](https://github.com/chrstphrknwtn/grid-clock-screensaver/commit/e1f0f163bd0f093e67474b48f541ae4b2e191587), committed 2019-01-15
- Reviewed through: [`e1f0f16`](https://github.com/chrstphrknwtn/grid-clock-screensaver/commit/e1f0f163bd0f093e67474b48f541ae4b2e191587), reviewed 2026-10-05

Every upstream commit after the fork point, through the reviewed one, is in
exactly one of the tables below. A port is a commit of this repository,
adapted to the fork; nothing is merged from upstream.

## Incorporated

| Upstream commit | Here | What |
| --- | --- | --- |

## Not incorporated

| Upstream commit | Why |
| --- | --- |

## Changes upstream does not have

| Change | Here |
| --- | --- |
| The clock is drawn natively with Core Text; the bundle loads no HTML, JavaScript or web engine at runtime (upstream's `WebView` stopped drawing on macOS 14, the fork's minimum) | [`ae86059`](https://github.com/forkcloser/grid-clock-screensaver/commit/ae86059) |
| Font sizing off the cell, replacing upstream's viewport units; the "last focused screen" display option is gone, since macOS 14 runs one saver per display: an existing "last focused" preference becomes "main display only" and "all screens" migrates as it is | [`ae86059`](https://github.com/forkcloser/grid-clock-screensaver/commit/ae86059) |
| Brightness option, 5 to 100 %, a multiplier on the two grey levels | [`1b01324`](https://github.com/forkcloser/grid-clock-screensaver/commit/1b01324) |
| The bundle carries its own version and build number, checked on the built product; the installer verifies the release's signed checksums before it fetches | https://github.com/forkcloser/grid-clock-screensaver/pull/9 |
| The timer sleeps between minute transitions and runs at 30 Hz only during the crossfade; a system time-zone change is read at the next minute | https://github.com/forkcloser/grid-clock-screensaver/pull/9 |
| The bundle identifier is the fork's, `org.forkcloser.grid-clock`, with the display and brightness settings carried over from the earlier domains on first launch (breaking: macOS sees a new saver) | https://github.com/forkcloser/grid-clock-screensaver/pull/9, https://github.com/forkcloser/grid-clock-screensaver/pull/73 |
