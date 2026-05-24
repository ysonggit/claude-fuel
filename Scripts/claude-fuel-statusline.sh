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

# Only overwrite when the incoming payload is actually fresher than what's
# on disk (same reset window + higher used_percentage, or newer window).
# This prevents a stale idle session from clobbering data written by an
# active session, or a refresh-daemon CLI session (separate auth) from
# overwriting desktop-app data.
maybe_write() {
  local incoming="$1"
  local target="$2"

  if [ ! -f "$target" ]; then
    echo "$incoming" > "$target"
    return
  fi

  local in_resets in_used ex_resets ex_used
  in_resets=$(echo "$incoming" | jq -r '.rate_limits.five_hour.resets_at // empty')
  in_used=$(echo "$incoming"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
  ex_resets=$(jq -r '.rate_limits.five_hour.resets_at // empty' "$target")
  ex_used=$(jq   -r '.rate_limits.five_hour.used_percentage // empty' "$target")

  # If incoming lacks rate-limit data, accept it anyway (it has other
  # useful fields like model, cost, context_window).
  if [ -z "$in_resets" ] || [ -z "$in_used" ]; then
    echo "$incoming" > "$target"
    return
  fi

  # If existing file lacks rate-limit data, accept incoming.
  if [ -z "$ex_resets" ] || [ -z "$ex_used" ]; then
    echo "$incoming" > "$target"
    return
  fi

  # Newer reset window → always accept.
  if [ "$in_resets" -gt "$ex_resets" ] 2>/dev/null; then
    echo "$incoming" > "$target"
    return
  fi

  # Same window, higher usage → accept (fresher reading).
  if [ "$in_resets" -eq "$ex_resets" ] 2>/dev/null; then
    if awk "BEGIN {exit !($in_used >= $ex_used)}" 2>/dev/null; then
      echo "$incoming" > "$target"
      return
    fi
  fi

  # Stale — skip this write.
}

# Always write when jq is unavailable (degraded mode).
if command -v jq &>/dev/null; then
  maybe_write "$input" "$status"
else
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
