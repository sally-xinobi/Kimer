# Kimer

A macOS desktop study companion. A small character lives on your screen, runs along while you type, and now keeps you on task with a built-in Pomodoro / focus timer.

Forked from [Gojaehyeon/keyhigh](https://github.com/Gojaehyeon/keyhigh) — extended with a study-timer feature, rebranded to **Kimer** (KeyHigh + Timer).

## Features

- **Typing companion**: chroma-keyed character (mouse / cat / etc.) animates faster the more you type.
- **Study timer (new)**: 15 / 25 / 50 minute focus presets plus a custom duration. Pause, resume, stop, and a daily focus total all live in the right-click menu.
- **Floating timer chip**: a draggable HUD appears above the desktop while a session runs, fades after a brief "DONE!" celebration.
- **System notification + chime** when a session ends, with a UNUserNotification fallback that fires even if the app is in the background.
- **Multiple characters**, sized Tiny → Large, persisted across launches. All settings via right-click; no Dock icon, no menu bar item.

## Run locally

```sh
./scripts/run.sh
```

First launch on macOS will ask for **Input Monitoring** permission — required for the typing-driven animation. Notifications permission is requested when the first session starts.

## Build a distributable

```sh
KIMER_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
KIMER_NOTARY_PROFILE="YOUR_NOTARY_PROFILE" \
./scripts/release.sh
```

The output `dist/Kimer-<version>.dmg` is signed, notarized, and stapled.

For local testing without a Developer ID, plain `./scripts/build.sh` ad-hoc signs into `.build/Kimer.app`.

## Adding characters

Drop `<name>_idle.{mov,mp4,m4v}` and `<name>_run.{mov,mp4,m4v}` pairs into `Resources/`. Green-screen background gets keyed to alpha automatically. The new character shows up in the right-click character picker on next launch.

## Credit

Original character widget by [Gojaehyeon](https://github.com/Gojaehyeon/keyhigh). Study timer extension by Sally.
