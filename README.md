# claude-fuel

A native macOS menu-bar companion for Claude Code that shows live token usage, rate-limit countdowns, and burn-rate projections — right in your notch.

## What it does

- **Notch island bar**: usage % + reset countdown displayed inside the macOS Dynamic Island / notch area
- **Menu bar gauge**: percentage + countdown always visible in your menu bar
- **Popover dashboard**: detailed breakdown with context window, model, cost, and projections
- **Burn-rate intelligence**: trend arrows, ETA-to-limit projections, 7-day pacing

## How usage data flows

claude-fuel does **not** estimate token counts from local files. It reads precise, server-side rate-limit data directly from Claude Code's status line feature.

### Data pipeline

```
Claude Code CLI
    │
    ├── statusLine hook (every 5s)
    │   └── ~/.claude/claude-fuel-statusline.sh
    │       └── writes status.json
    │
    └── background refresh daemon (every 60s)
        └── claude -p "." --bare
            └── triggers status line → writes status.json

         ┌─────────────────┐
         │   status.json   │  ~/Library/Application Support/dev.ysong.claude-fuel/
         └────────┬────────┘
                  │
    StatusLineWatcher (DispatchSource + 10s polling fallback)
                  │
              AppState
              ┌───┴───┐
         Island Bar  Popover
```

### What's in status.json

Claude Code's status line payload contains server-side data — no local estimation:

| Field | Source | What it tells you |
|---|---|---|
| `rate_limits.five_hour.used_percentage` | Anthropic API response headers | Account-wide 5h window usage (0-100) |
| `rate_limits.five_hour.resets_at` | API headers | Unix epoch when the 5h window resets |
| `rate_limits.seven_day.used_percentage` | API headers | Account-wide 7-day window usage |
| `rate_limits.seven_day.resets_at` | API headers | Unix epoch when the 7-day window resets |
| `context_window.used_percentage` | API response | How full the current session's context is |
| `context_window.current_usage` | API response | Token breakdown for the latest turn |
| `model.display_name` | Session state | Active model (Opus, Sonnet, Haiku) |
| `cost.total_cost_usd` | Session state | Cumulative session cost |

### How metrics are computed

**Remaining percentage**: straight from `100 - used_percentage`. No estimation, no weighting — this is the exact value Anthropic's server reports.

**Reset countdown**: `resets_at` epoch minus current time. Shown as both duration ("2h 47m") and absolute clock time ("5:30 PM").

**Burn rate**: a ring buffer stores the last ~720 `(timestamp, used_percentage)` snapshots from the status line. The burn rate (% per hour) is computed as:

```
burn_rate = (latest_used% - earliest_used%) / time_elapsed_hours
```

Only snapshots from the current rate-limit window (same `resets_at`) are used. The buffer is cleared on window reset.

**Trend arrow** (island bar): the snapshot buffer is split in half. If the second half's rate exceeds the first half's by >30%, the arrow shows accelerating. If it's <70%, cooling. Otherwise steady.

**ETA to limit**: `remaining% / burn_rate_per_hour`, expressed as a duration. When ETA < time-until-reset, the popover shows a warning — you'll likely hit the limit before the window resets.

**7-day pacing**: compares actual usage vs expected usage based on elapsed time in the 7-day window:

```
expected_used% = (elapsed_time / 7_days) * 100
ratio = actual_used% / expected_used%
```

- ratio < 0.8 → under pace (green)
- ratio 0.8–1.2 → on pace (neutral)
- ratio > 1.2 → over pace (amber)

### Background refresh

Rate limits are account-wide but only returned in API response headers. If you work in the Claude desktop app, the CLI session's cached rate limits go stale. The app launches a background daemon every 60 seconds that starts a minimal interactive Claude Code session (using `script` to fake a TTY), sends a single-character prompt with `--max-turns 1`, and exits. Because the session is interactive (not `-p`/print mode), the statusLine hook fires on the API response, writing fresh rate-limit data to status.json. This keeps the display within ~1 minute of reality regardless of which Claude client you use.

### Staleness handling

When the status line's `resets_at` is in the past, the rate-limit window has expired and the data reflects a previous window. The app still displays the last known percentage (with an amber "stale" indicator) rather than showing nothing.

## Setup

### Prerequisites

- macOS 14+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `jq` (for the status line script): `brew install jq`

### Install

1. Build and run from Xcode:
   ```bash
   git clone https://github.com/ysonggit/claude-fuel.git
   cd claude-fuel
   open ClaudeFuel.xcodeproj
   # Cmd-R to run
   ```

2. Configure Claude Code's status line in `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/claude-fuel-statusline.sh",
       "refreshInterval": 5
     }
   }
   ```

3. Install the scripts:
   ```bash
   cp Scripts/claude-fuel-statusline.sh ~/.claude/
   cp Scripts/claude-fuel-refresh.sh ~/.claude/
   chmod +x ~/.claude/claude-fuel-statusline.sh ~/.claude/claude-fuel-refresh.sh
   ```

4. Start an interactive `claude` session in a terminal — the meter appears immediately.

### Settings

- **Island bar**: toggle the notch overlay on/off in Settings > General
- The app stores config in `~/Library/Application Support/dev.ysong.claude-fuel/`

## Architecture

Pure Swift/SwiftUI, zero dependencies. ~1500 lines of code.

| Layer | Key files |
|---|---|
| Data | `StatusLineWatcher.swift`, `StatusLineData.swift` |
| State | `AppState.swift`, `UsageSnapshot.swift` |
| Island | `IslandPanelController.swift`, `IslandContentView.swift` |
| Popover | `PopoverView.swift` |
| Design | `Colors.swift`, `Typography.swift`, `Spacing.swift` |
| Scripts | `claude-fuel-statusline.sh`, `claude-fuel-refresh.sh` |

## License

MIT
