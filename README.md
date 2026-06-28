# Claude Usage

A lightweight macOS menu bar app that shows your daily Claude Code token usage and estimated API cost — read directly from local logs, no account needed.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- Displays today's token usage (input / output / cache) and estimated cost in the menu bar
- Reads usage directly from `~/.claude/projects/**/*.jsonl` — no API key required
- Optional Admin API integration for org accounts
- Switches between cost view (`$0.0123`) and token count view (`42.1K`)
- Auto-refreshes on a configurable interval
- Uses Claude Desktop's tray icon if installed

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (for `swiftc`)
- [Claude Desktop](https://claude.ai/download) installed (for the tray icon — optional)

Install Xcode Command Line Tools if you haven't already:

```bash
xcode-select --install
```

## Installation

### Option 0 — Download the pre-built installer (optional)

A pre-built `ClaudeUsage-1.0.pkg` is available in this repository. Download and double-click it to install directly to `/Applications/` — no build tools required.

> **Note:** The package is unsigned, so macOS may warn you. Go to **System Settings → Privacy & Security** and click **Open Anyway** if prompted.

### Option 1 — Build and install directly (recommended)

1. Clone this repo and copy the files to `~/.config/claude-usage/`:

```bash
git clone https://github.com/hummingbird1986/claude-usage.git
mkdir -p ~/.config/claude-usage
cp claude-usage/ClaudeUsage.swift ~/.config/claude-usage/
cp claude-usage/build.sh ~/.config/claude-usage/
```

2. Run the build script:

```bash
bash ~/.config/claude-usage/build.sh
```

This compiles the Swift source, creates `~/Applications/ClaudeUsage.app`, copies the tray icon from Claude Desktop, and signs the bundle with an ad-hoc signature.

3. Launch the app:

```bash
open ~/Applications/ClaudeUsage.app
```

You should see a token/cost indicator appear in your menu bar.

### Option 2 — Build a .pkg installer

To produce a double-click installer. The `.pkg` will be generated in the same directory as `package.sh`:

```bash
cp claude-usage/package.sh ~/.config/claude-usage/
bash ~/.config/claude-usage/package.sh
```

Double-click the resulting `.pkg` to install to `/Applications/`.

## Auto-start at Login

Go to **System Settings → General → Login Items** and add `ClaudeUsage.app`.

## Configuration (optional)

Create `~/.config/claude-usage/config.json` to customise behaviour:

```json
{
  "daily_budget": 5.00,
  "refresh_interval": 60
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `daily_budget` | `0` (disabled) | Shows a warning (⚠) when cost reaches 90% of this amount |
| `refresh_interval` | `60` | Refresh interval in seconds |

## Admin API (org accounts only)

Personal Claude accounts don't need this — usage is read from local logs automatically.

If you have an **org account** with an Admin API key, click **Set Admin Key (Org Account)…** in the menu to store it securely in Keychain. The app will then pull live usage data from the Anthropic API instead of local logs.

To get an Admin API key: [Anthropic Console](https://console.anthropic.com) → Settings → API Keys → Admin Keys.

## License

MIT
