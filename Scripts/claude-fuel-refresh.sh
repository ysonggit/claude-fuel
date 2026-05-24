#!/bin/bash
# Periodically pings Claude Code with a minimal prompt to refresh
# account-wide rate limits. Runs as a background daemon managed by
# claude-fuel.app.
#
# The statusLine hook only fires in interactive mode (not -p/--print).
# We use `script` to fake a TTY so Claude Code enters interactive mode,
# sends a tiny prompt, and exits after one turn — triggering the hook.
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
  # Interactive session with faked TTY. --max-turns 1 ensures exit after
  # one API round-trip. The statusLine hook fires on the API response,
  # writing fresh rate-limit data to status.json.
  script -q /dev/null bash -c 'printf ".\n" | claude --max-turns 1 2>/dev/null' >/dev/null 2>&1
  sleep "$interval"
done
