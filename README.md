# Claude Usage Menu Bar

A native macOS menu bar app that displays your Claude Code subscription usage with circular progress rings, model detection, and token activity tracking.

## Install

1. Download **ClaudeUsageMenuBar-v1.0.0.zip** from [Releases](https://github.com/bensonhon/claude-usage-menu-bar/releases)
2. Extract the zip
3. Move **ClaudeUsageMenuBar.app** to `/Applications`
4. Right-click the app → **Open** (first time only, to bypass Gatekeeper)

### Requirements

- macOS 14 (Sonoma) or later
- Logged in to Claude Code (OAuth token in Keychain)

## Features

- **Menu bar icon** — Claude logo + usage ring with percentage + session reset time
- **Color-coded rings** — Green (>30%), amber (10-30%), red (<10%) remaining
- **Session & weekly rings** — 5-hour and 7-day usage at a glance
- **Per-model usage bars** — Sonnet, Opus, Omelette, and other model breakdowns
- **Current model detection** — Shows which Claude model you're using (e.g. Opus 4.6)
- **Token activity** — Today/week/month token counts with input/output/cache breakdown
- **Extra usage tracking** — Credits used and monthly limit if enabled
- **Auto-refresh** — Updates every 60 seconds

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
3. Parses `~/.claude/projects/**/*.jsonl` files for token history and current model
4. Displays everything in a dark-themed popover from the menu bar
