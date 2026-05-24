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

new_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0' 2>/dev/null)
old_resets=0
if [ -f "$status" ]; then
  old_resets=$(jq -r '.rate_limits.five_hour.resets_at // 0' "$status" 2>/dev/null)
fi

if [ "${new_resets:-0}" -ge "${old_resets:-0}" ]; then
  echo "$input" > "$status"
fi

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
