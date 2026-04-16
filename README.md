# Claude Usage Monitor

A native macOS menu bar app that displays your Claude Code subscription usage as beautiful circular progress rings.

## Features

- **Menu bar icon** — Small circular ring showing your 5-hour session remaining percentage
- **Two main progress rings** — Session (5h) and Weekly (7d) usage at a glance
- **Model-specific usage** — Sonnet, Opus, Haiku breakdowns with horizontal progress bars
- **Extra usage tracking** — Credits used and monthly limit visualization
- **Token activity** — Today/week/month token counts parsed from local JSONL logs
- **Auto-refresh** — Updates every 60 seconds

## Requirements

- macOS 14.0 (Sonoma) or later
- Claude Code installed and authenticated (OAuth token in Keychain)

## Build

```bash
chmod +x build.sh
./build.sh
```

Or open `ClaudeUsageMenuBar.xcodeproj` in Xcode and build directly.

## How It Works

1. Reads your OAuth token from macOS Keychain (`Claude Code-credentials`)
2. Calls `https://platform.claude.com/api/oauth/usage` to get usage windows
3. Parses `~/.claude/projects/**/*.jsonl` files for token activity history
4. Displays everything in a polished dark-themed popover from the menu bar
