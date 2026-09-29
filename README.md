# Claude Usage Menu Bar

A native macOS menu bar app that displays your Claude Code subscription usage with circular progress rings, model detection, and token activity tracking.

## Install

1. Download the latest **ClaudeUsageMenuBar-vX.Y.Z.dmg** from [Releases](https://github.com/bensonhon/claude-usage-menu-bar/releases)
2. Open the DMG (the volume is named **Claude Usage Monitor**)
3. Drag **ClaudeUsageMenuBar** onto the **Applications** shortcut next to it
4. Eject the DMG
5. Open **ClaudeUsageMenuBar** from Applications. The app is not notarized yet, so the first launch is blocked by Gatekeeper. How to allow it depends on your macOS version:
   - **macOS 15 (Sequoia) and later:** macOS shows *"ClaudeUsageMenuBar" Not Opened*. Click **Done**, then open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to *"ClaudeUsageMenuBar" was blocked…*. Confirm the follow-up dialog with **Open Anyway** and your password or Touch ID. Right-click → **Open** no longer bypasses this dialog on macOS 15.
   - **macOS 13–14:** right-click the app → **Open**, then click **Open** in the dialog.
   - **Any version, from Terminal:** run `xattr -dr com.apple.quarantine /Applications/ClaudeUsageMenuBar.app` right after step 3, before the first launch. It removes the download quarantine so the app opens normally. (Once Gatekeeper has blocked a launch, macOS may refuse this with "Operation not permitted". Use the System Settings route above instead.)

### Requirements

- macOS 13 (Ventura) or later
- Universal binary — runs natively on both Apple Silicon and Intel Macs (no Rosetta required)
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

To package a release DMG (the app plus an Applications shortcut), run:

```bash
./make-dmg.sh
```

This runs `build.sh`, checks the code signature, and writes `build/ClaudeUsageMenuBar-vX.Y.Z.dmg`.

## How It Works

1. Reads your OAuth token from macOS Keychain (`Claude Code-credentials`)
2. Calls the Claude usage API to get session, weekly, and per-model usage windows
3. Parses `~/.claude/projects/**/*.jsonl` files (in parallel, tail-only) for token history, current model, and recent sessions
4. Displays everything in a light/dark-themed popover from the menu bar

## Caveats

- **Claude Code CLI only.** Claude Desktop users are not supported — Desktop encrypts its credentials via Electron's `safeStorage` and writes no activity files to `~/.claude/projects/`, so neither the usage API nor the session/token history are reachable.
- **No OAuth refresh.** If your CLI access token expires, the menu bar shows a no-data state (`?` rings, `—` plan badge) until the next time you use `claude` and the CLI refreshes the token.
- **Token counts are approximate.** Each JSONL is read tail-only (last ~128 KB) for speed; very long sessions may slightly undercount.
