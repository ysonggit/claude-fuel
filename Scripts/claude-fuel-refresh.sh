#!/bin/bash
# Periodically pings Claude Code with a minimal prompt to refresh
# account-wide rate limits. Runs as a background daemon managed by
# claude-fuel.app.
#
# The statusLine hook only fires in interactive mode (not -p/--print).
# We use `script` to fake a TTY so Claude Code enters interactive mode,
# sends a tiny prompt, and gets one API response — triggering the hook.
#
# Interactive claude never exits on its own (--max-turns limits tool
# iterations, not conversation turns). We background the process, wait
# 30s, then kill the entire process tree. The statusLine fires within
# ~10s of the API response, so status.json is updated before the kill.
#
# Usage: claude-fuel-refresh.sh [interval_seconds]
# Default interval: 60 seconds

interval="${1:-60}"
dir="$HOME/Library/Application Support/dev.ysong.claude-fuel"
pidfile="$dir/refresh.pid"

# Write PID so the app can stop us.
echo $$ > "$pidfile"

# Recursively kill a process and all its descendants.
kill_tree() {
  local pid=$1
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    kill_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null
}

# On exit, clean up PID file and kill any child processes.
cleanup() {
  rm -f "$pidfile"
  kill_tree $$ 2>/dev/null
  exit 0
}
trap cleanup INT TERM

while true; do
  # Start interactive session in background.
  script -q /dev/null bash -c 'printf ".\n" | claude --max-turns 1 2>/dev/null' \
    >/dev/null 2>&1 &
  refresh_pid=$!

  # Wait up to 30s for the API response (statusLine fires ~5-10s in).
  sleep 30

  # Kill the entire process tree (script → bash → claude).
  kill_tree $refresh_pid
  wait $refresh_pid 2>/dev/null

  sleep "$interval"
done
