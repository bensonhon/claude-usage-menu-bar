# Claude Usage Menu Bar

A native macOS menu bar app that displays your Claude Code subscription usage with circular progress rings, model detection, and token activity tracking.

## Install

1. Download the latest **ClaudeUsageMenuBar-vX.Y.Z.dmg** from [Releases](https://github.com/bensonhon/claude-usage-menu-bar/releases)
2. Open the DMG
3. Drag **Claude Usage Monitor** to the **Applications** folder
4. Eject the DMG
5. Open the app from Applications — right-click → **Open** the first time (the app is not notarized yet, so Gatekeeper will block a plain double-click)

### Requirements

- macOS 14 (Sonoma) or later
- **Claude Code CLI** signed in (OAuth token in Keychain). Claude Desktop users are **not** supported — Desktop's credentials are encrypted separately and its activity doesn't write to `~/.claude/projects/`, so neither usage data nor token history can be read.

## Features

- **Menu bar icon** — Claude logo + usage ring with percentage + session reset time. Shows `?` when no data is available.
- **Color-coded rings** — Green (>30%), amber (10-30%), red (<10%) remaining
- **Session & weekly rings** — 5-hour and 7-day usage at a glance
- **Per-model usage bars** — Sonnet, Opus, Haiku, and other model breakdowns
- **Recent Sessions card** — Last 10 days of Claude Code sessions with project name, model, and how long ago it was used. Auto-scrolls (credits-style) with 3 rows visible; hover to pause and scroll manually.
- **Token activity** — Today / Last 3 Days / Last 7 Days token counts with input/output/cache breakdown for today
- **Extra usage tracking** — Credits used and monthly limit if enabled
- **Light/dark mode** toggle
- **Adaptive refresh** — 60 s when signed in, 15 s while waiting for sign-in to catch up quickly
- **Quit button** (⌘Q) in the popover footer
- **Skeleton placeholders** while the JSONL history is being parsed on launch
- **Fast parse** — per-file concurrent parse via `TaskGroup`, tail-only read of each JSONL

## Build from Source

Requires Swift and Command Line Tools (`xcode-select --install`).

```bash
chmod +x build.sh
./build.sh
```

**Note:** If compilation fails with a `SwiftBridging` module error, run:
```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.bak
```
This is a known Apple Command Line Tools bug.

## How It Works

1. Reads your OAuth token from macOS Keychain (`Claude Code-credentials`)
2. Calls the Claude usage API to get session, weekly, and per-model usage windows
3. Parses `~/.claude/projects/**/*.jsonl` files (in parallel, tail-only) for token history, current model, and recent sessions
4. Displays everything in a light/dark-themed popover from the menu bar

## Caveats

- **Claude Code CLI only.** Claude Desktop users are not supported — Desktop encrypts its credentials via Electron's `safeStorage` and writes no activity files to `~/.claude/projects/`, so neither the usage API nor the session/token history are reachable.
- **No OAuth refresh.** If your CLI access token expires, the menu bar shows a no-data state (`?` rings, `—` plan badge) until the next time you use `claude` and the CLI refreshes the token.
- **Token counts are approximate.** Each JSONL is read tail-only (last ~128 KB) for speed; very long sessions may slightly undercount.
