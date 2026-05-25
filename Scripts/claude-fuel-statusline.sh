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
    # The incoming session made fewer (or zero) API calls. When the drop is
    # drastic (≤ 1%), we're fully rate-limited — write used_percentage=100
    # so the island shows 0% remaining instead of stale data.
    if (( $(echo "$incoming_used <= 1" | bc -l 2>/dev/null || echo 0) )); then
      jq '.rate_limits.five_hour.used_percentage = 100' "$status" > "$status.tmp" \
        && mv "$status.tmp" "$status"
    else
      touch "$status"   # moderate drop: preserve existing, update mtime
    fi
    exit 0
  fi
fi
echo "$input" > "$status"

# Echo compact status for Claude Code's terminal UI.
if command -v jq &>/dev/null; then
  used_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
  resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // ""')

  # Build progress bar: 10 cells
  bar_len=10
  filled=$(( used_pct * bar_len / 100 ))
  empty=$(( bar_len - filled ))
  bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  # Compute time remaining until reset (resets_at is unix epoch)
  reset_str=""
  if [[ -n "$resets_at" && "$resets_at" != "null" && "$resets_at" != "0" ]]; then
    now_epoch=$(date +%s)
    diff=$(( resets_at - now_epoch ))
    if (( diff > 0 )); then
      hrs=$(( diff / 3600 ))
      mins=$(( (diff % 3600) / 60 ))
      reset_str=" resets ${hrs}h${mins}m"
    fi
  fi

  echo "[${bar}] ${used_pct}%${reset_str}"
else
  echo "claude-fuel: status updated"
fi
