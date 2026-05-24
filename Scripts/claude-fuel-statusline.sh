#!/bin/bash
# Claude Code Status Line script for claude-fuel.
# Receives JSON on stdin, writes to status.json for the menu-bar app,
# echoes a compact line back to Claude Code's UI.
#
# Multiple sessions may call this concurrently. We only overwrite when
# the incoming payload's resets_at >= what's already on disk, so a stale
# idle session can never clobber fresher data.

input=$(cat)

dir="$HOME/Library/Application Support/dev.ysong.claude-fuel"
mkdir -p "$dir"
status="$dir/status.json"

# Guard against stale/rate-limited sessions: a session that hit a rate
# limit reports used_percentage=0 (no API calls were made). Never
# clobber real quota data with zero-usage data from a blocked session.
if [[ -f "$status" ]] && command -v jq &>/dev/null; then
  incoming=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0')
  existing=$(jq -r '.rate_limits.five_hour.used_percentage // 0' "$status")
  if (( $(echo "$incoming < $existing" | bc -l 2>/dev/null || echo 0) )); then
    # Incoming is lower — likely a rate-limited session with no API calls.
    # Keep existing data but update the file mtime so staleness tracking works.
    touch "$status"
    exit 0
  fi
fi
echo "$input" > "$status"

# Echo compact status for Claude Code's terminal UI.
if command -v jq &>/dev/null; then
  model=$(echo "$input" | jq -r '.model.display_name // "?"')
  five_h=$(echo "$input" | jq -r '100 - (.rate_limits.five_hour.used_percentage // 0)' | cut -d. -f1)
  seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
  ctx=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
  echo "[$model] 5h:${five_h}% left 7d:${seven_d}% used ctx:${ctx}%"
else
  echo "claude-fuel: status updated"
fi
