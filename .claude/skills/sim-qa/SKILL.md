---
name: sim-qa
description: Run, drive and inspect the Volspire iOS app in the simulator to debug or verify a change — build + install + launch, tap/type/swipe through screens with an XCUITest driver, screenshots at point size, screen recordings split into frames for animations, app logs, UserDefaults, and temporary QA-TEMP launch hooks. Use when asked to reproduce a bug on the simulator, check a change in the running app, or capture how something looks or animates.
---

# Simulator QA for Volspire (iOS)

Everything lives in `.claude/skills/sim-qa/`: `scripts/` (shell helpers) and `driver/` (a tiny XCUITest project that drives the app from the shell).

## When to use it

- Use it when a bug needs reproducing, when you need to prove a fix works in the running app, or when Hector asks for screenshots or recordings.
- **Don't** use it for small visual tweaks. For those, build only and let Hector check visually himself (memory: user-does-visual-checks).

## Setup for the session

Point the work dir at the session scratchpad, so builds, screenshots and driver io stay out of the repo:

```bash
export QA_DIR=<scratchpad>/sim-qa   # every script reads it; defaults to $TMPDIR/volspire-sim-qa
S=.claude/skills/sim-qa/scripts
```

Shell state doesn't persist between Bash calls, so put `QA_DIR=… ` in front of each command (or `export` it in the same call).

### Accounts: use the demo account

Always test signed in as the **App Review demo account**, `appreview@volspire.com` (@lowkeyloops), never Hector's own accounts.

- `scripts/signin.sh` signs in with it whenever the app is on the Welcome or login screen, and dismisses iOS's "Save Password?" prompt. Run it after `driver.sh start`.
- Credentials live **outside the repo** in `~/.config/volspire/demo.env` (`DEMO_EMAIL`, `DEMO_PASSWORD`). Never write them into the repo.
- To use a different account for one run, set `DEMO_EMAIL=… DEMO_PASSWORD=…`.
- The demo account is App Review's: it must survive. Don't delete it, change its password, or post, message, follow or edit with it unless Hector says so. Never interact with the `nvs` account from it.
- For a throwaway (e.g. deletion or onboarding flows), register a new account on the signed-out SE sim rather than reusing the demo one.

### Simulators

| UDID | State | Pass |
|---|---|---|
| `A77F9C00-A82A-422F-9E6E-EC34152422F1` | Signed in (demo account via `signin.sh`); the default | `SIM=` (default) |
| `A16B42EA…` (iPhone SE) | Signed out, for auth/onboarding flows | `SIM=<udid> SCALE=2` |

Find the full SE UDID with `xcrun simctl list devices available | grep -i SE`. Toggle light/dark with `xcrun simctl ui $SIM appearance light|dark`.

These UDIDs only exist on Hector's main Mac. On any other machine `env.sh` falls back automatically: first a booted iPhone, then the newest available non-SE iPhone. So the scripts work on a new laptop without edits; pass `SIM=` to pick a specific one.

The Android counterpart is the `android-qa` skill in the volspire-android repo. Its `compare.sh` takes matching iOS + Android screenshots for parity checks.

## The loop

```bash
$S/build.sh                          # errors/warnings + "** BUILD SUCCEEDED **" only
$S/launch.sh                         # boot if needed, reinstall the build, relaunch
$S/driver.sh start                   # ~20–40s: builds + starts the XCUITest driver
$S/signin.sh                         # signs in with the demo account if on Welcome/login; no-op otherwise
$S/drv.sh "labels"                   # what's on screen: type, frame (pt), label, id
$S/drv.sh "tap Messages" "wait 1.5" "labels"
$S/shot.sh messages                  # → $QA_DIR/shots/messages.png at point size
```

Then `Read` the PNG to look at it.

After a rebuild, run `launch.sh` again. The driver keeps running across relaunches: follow the relaunch with `drv.sh activate`. Restart the driver only if `drv.sh` prints `TIMEOUT`. Run `driver.sh stop` when you're done.

### Driver commands

Pass several commands to one `drv.sh` call; they run in order.

| Command | What it does |
|---|---|
| `tap <label>` / `tap <label>#n` | Taps the first (or n-th) hittable element whose label or identifier matches exactly, then falls back to a case-insensitive "contains" match. Lucide icons expose ids like `lucide-chevron-left`. |
| `tapxy x y` | Taps at a point. Screenshots are at point size, so the pixel coordinates in a `shot.sh` image are tap coordinates. |
| `longxy x y` | Presses for 1s at a point. |
| `drag x1 y1 x2 y2` | Drags between two points. Use it for sheets, pagers, the player and scrubbing; the feed pager is verified with scripted drags. |
| `swipeup` / `swipedown` / `swipeleft` / `swiperight` | Swipes. |
| `type <text>` | Types into the focused field. |
| `clear <label>` | Focuses a field and empties it. |
| `wait <s>` | Waits. |
| `activate`, `launch`, `terminate` | App lifecycle. |
| `labels` | Lists every labelled element with its frame. |
| `dump` | The full accessibility tree, for when `labels` isn't enough. |

Prefer `tap <label>` over coordinates; it survives layout changes. When a SwiftUI control has no label, read its frame from `labels` or the screenshot and use `tapxy`.

## Animations and transitions

```bash
$S/record.sh sheet-open 4 10 -- "tap Filters"   # name, seconds, fps, then optional drv commands
```

This records the screen while the commands run, then writes `sheet-open.mp4` plus `sheet-open_NNN.png` frames at point size. `Read` a handful of frames (start, middle, end) rather than all of them. It's good for catching flashes, wrong-direction transitions, blinking materials and stuck states.

## Logs and state

```bash
$S/logs.sh 5 "[ConversationVM]"      # last 5 min of the app's logs, optionally filtered
$S/defaults.sh                       # dump the app's UserDefaults
$S/defaults.sh delete <key>          # e.g. reset an intro modal: volspire:intro-dismissed:<id>
```

- `debugLog(...)` output shows up in `logs.sh`.
- For a live tail, launch with `--console-pty` directly instead: `SIMCTL_CHILD_X=1 xcrun simctl launch --console-pty $SIM com.volspire.app > $QA_DIR/console.txt 2>&1 &`.
- UserDefaults live in the app's data container, which `xcrun simctl spawn … defaults` can't see. That's why `defaults.sh` exists.

## QA-TEMP launch hooks (reaching deep state fast)

When driving there by taps is slow or flaky, add a **temporary** hook in the app that reads a launch env var. Mark it so it can be found and removed:

```swift
// QA-TEMP
if let name = ProcessInfo.processInfo.environment["QA_OPEN_CONVO"] { /* navigate straight there */ }
```

Launch with `$S/launch.sh QA_OPEN_CONVO=psyknick`, which becomes `SIMCTL_CHILD_QA_OPEN_CONVO`. Past hooks:

- `QA_OPEN_CONVO=<username>`
- `QA_FEED=hold|fast` and `QA_START=<title>` (feed pager)
- `QA_RAIL=1`

**Always remove them before finishing.** Confirm `grep -rn "QA-TEMP" VolspireCore DesignSystem` is empty, then rebuild.

## Ground rules

- **Never** commit or touch git state. Hector makes all commits.
- Don't change real or demo account data while testing: no posting, messaging, following or deleting on real accounts. Mutations need Hector's OK. Reading is fine.
- The production Supabase DB is shared. Testing on the sim hits it for real.
- Simulator audio glitches (AVAudioEngine RPC timeouts) are simulator noise, not app bugs.
- A brand-new `.swift` file builds with xcodebuild, but an open Xcode won't see it until it's reopened.
- Report what you saw: name the screenshot and recording paths, and say plainly if something couldn't be reproduced.
