# CCUsage Taskbar

A tiny native macOS menu bar app for showing local AI coding usage from [`ccusage`](https://github.com/ccusage/ccusage).

It can show Claude Code or Codex usage as:

- cost, with useful precision like `$2.34`, `$12.3`, or `$123`
- total tokens, formatted as `K`, `M`, or `B`
- output tokens, formatted as `K`, `M`, or `B`

The app refreshes every 10 minutes and includes a manual **Refresh** menu item.

## Features

- Native AppKit menu bar app
- Claude / Codex switcher
- Display mode switcher for cost, total tokens, or output tokens
- Time ranges:
  - Today
  - Past 24 hours
  - Past 7 days
  - Month to date
  - Past 30 days
  - Year to date
- Optional launch at login
- Configurable `ccusage` executable path

## Install ccusage First

This app shells out to `ccusage`, so install that first and verify it works in Terminal.

Global install options:

```sh
npm install -g ccusage
```

```sh
bun install -g ccusage
```

```sh
pnpm add -g ccusage
```

Then verify:

```sh
ccusage --version
ccusage claude --since 2026-01-01 --json
ccusage codex --since 2026-01-01 --json
```

If `ccusage` is not on the PATH available to GUI apps, open this app's **Preferences...** menu item and set the executable to an absolute path, for example:

```sh
/opt/homebrew/bin/ccusage
```

or:

```sh
~/.asdf/shims/ccusage
```

## How Ranges Work

Calendar-date ranges use daily totals:

```sh
ccusage claude --since YYYY-MM-DD --json
ccusage codex --since YYYY-MM-DD --json
```

Those ranges are:

- Today
- Past 7 days
- Month to date
- Past 30 days
- Year to date

Past 24 hours is a close-enough rolling window. It uses:

```sh
ccusage <provider> session --since YYYY-MM-DD --json
```

and totals sessions whose `lastActivity` is inside the last 24 hours. This is approximate because `ccusage` session output does not expose per-event timestamps for splitting a long session across the exact cutoff.

## Build

Requirements:

- macOS 13+
- Swift toolchain / Xcode Command Line Tools
- `ccusage` installed

Build the app:

```sh
./scripts/build-app.sh
```

The built app is written to:

```sh
.build/app/CCUsage Taskbar.app
```

Run it:

```sh
open ".build/app/CCUsage Taskbar.app"
```

## Launch at Login

Use the app menu's **Launch at Login** toggle.

It writes or removes:

```sh
~/Library/LaunchAgents/io.github.wangtian24.ccusage-taskbar.plist
```

## Development

Run directly from Terminal:

```sh
swift run CCUsageTaskbar
```

Package a release app bundle:

```sh
./scripts/build-app.sh
```
