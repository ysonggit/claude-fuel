#!/bin/bash
# Periodically pings Claude Code with a minimal prompt to refresh
# account-wide rate limits. Runs as a background daemon managed by
# claude-fuel.app.
#
# Usage: claude-fuel-refresh.sh [interval_seconds]
# Default interval: 60 seconds

interval="${1:-60}"
dir="$HOME/Library/Application Support/dev.ysong.claude-fuel"
pidfile="$dir/refresh.pid"

# Write PID so the app can stop us.
echo $$ > "$pidfile"
trap 'rm -f "$pidfile"; exit 0' INT TERM

while true; do
  # Minimal non-interactive call. The API response headers include
  # current rate limits; the status line script captures them.
  echo "." | claude -p --max-turns 1 --bare >/dev/null 2>&1
  sleep "$interval"
done
