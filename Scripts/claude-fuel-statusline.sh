#!/bin/bash
# Claude Code Status Line script for claude-fuel.
# Receives JSON on stdin, writes to status.json for the menu-bar app,
# echoes a compact line back to Claude Code's UI.
#
# Multiple sessions may call this concurrently. We guard against
# rate-limited sessions that report used_percentage=0 — see the
# guard block below for details.

input=$(cat)

dir="$HOME/Library/Application Support/dev.ysong.claude-fuel"
mkdir -p "$dir"
status="$dir/status.json"

# Guard against stale/rate-limited sessions overwriting real quota data.
# A rate-limited session makes zero API calls, so its statusLine reports
# used_percentage=0 even though the real quota is exhausted. Within the
# same five-hour window, a lower used_pct means the incoming session did
# less real work than what's already recorded — reject it.
#
# Across window boundaries (resets_at changed), a drop to 0% is a genuine
# quota reset — accept the write.
if [[ -f "$status" ]] && command -v jq &>/dev/null; then
  incoming_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0')
  incoming_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
  existing_used=$(jq -r '.rate_limits.five_hour.used_percentage // 0' "$status")
  existing_reset=$(jq -r '.rate_limits.five_hour.resets_at // 0' "$status")

  # Same window + incoming reports lower usage → rate-limited/stale session.
  if (( incoming_reset == existing_reset )) \
     && (( $(echo "$incoming_used < $existing_used" | bc -l 2>/dev/null || echo 0) )); then
    touch "$status"   # update mtime so staleness tracking works
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
