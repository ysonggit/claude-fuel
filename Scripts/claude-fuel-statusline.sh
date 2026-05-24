#!/bin/bash
# Claude Code Status Line script for claude-fuel.
# Receives JSON from Claude Code's stdin, writes it to the app's data
# directory for the menu-bar app to read, and echoes a compact status
# line back to Claude Code's UI.
#
# Install:
#   1. chmod +x ~/.claude/claude-fuel-statusline.sh
#   2. Add to ~/.claude/settings.json:
#      { "statusLine": { "type": "command", "command": "~/.claude/claude-fuel-statusline.sh", "refreshInterval": 5 } }

input=$(cat)

dir="$HOME/Library/Application Support/dev.ysong.claude-fuel"
mkdir -p "$dir"

# Multiple Claude sessions can call this script. Only let payloads with a
# current 5-hour window update the app; expired rate-limit blocks are stale
# snapshots and must not overwrite a newer account-level usage reading.
now=$(date +%s)
new_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0' 2>/dev/null)
if [ "${new_resets:-0}" -gt "$now" ]; then
  echo "$input" > "$dir/status.json"
fi

# Echo compact status line for Claude Code's UI.
if command -v jq &>/dev/null; then
  model=$(echo "$input" | jq -r '.model.display_name // "?"')
  five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
  five_h_left=$(echo "$input" | jq -r '100 - (.rate_limits.five_hour.used_percentage // 0)' | cut -d. -f1)
  if [ "$five_h_reset" -gt 0 ] && [ "$now" -ge "$five_h_reset" ]; then
    five_h_suffix=" stale"
  else
    five_h_suffix=""
  fi
  seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
  ctx=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
  echo "[$model] 5h:${five_h_left}% left${five_h_suffix} 7d:${seven_d}% used ctx:${ctx}%"
else
  echo "claude-fuel: status updated"
fi
