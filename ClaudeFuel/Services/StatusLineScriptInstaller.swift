import CryptoKit
import Foundation

/// Installs and verifies the Claude Code statusLine script at
/// `~/.claude/claude-fuel-statusline.sh`.
///
/// Claude Code invokes the path configured in `~/.claude/settings.json` on
/// every prompt redraw. We had a regression where edits in the repo's
/// `Scripts/claude-fuel-statusline.sh` never reached runtime because the
/// installed copy was an older revision — the menu bar happily reported
/// the stale `status.json` the bad script kept writing. This service
/// detects that drift and lets the user one-click reinstall.
///
/// The canonical script lives below as a Swift string so the bundled app
/// is a self-contained source of truth. Keep `Scripts/claude-fuel-statusline.sh`
/// byte-identical to `canonicalScript` — the runtime hash check will flag
/// any divergence, and an in-repo diff between the two is the intended
/// way to keep them aligned.
enum StatusLineScriptInstaller {
    enum InstallState: Equatable {
        case notInstalled
        case upToDate
        case outOfDate
    }

    static var installedPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claude-fuel-statusline.sh")
    }

    static func currentState() -> InstallState {
        let url = installedPath
        guard let data = try? Data(contentsOf: url) else { return .notInstalled }
        return hash(of: data) == canonicalHash ? .upToDate : .outOfDate
    }

    /// Writes the canonical script and makes it executable. Creates `~/.claude`
    /// if missing. Throws on filesystem failures so the UI can surface the
    /// error rather than silently lie about success.
    static func install() throws {
        let url = installedPath
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try canonicalScript.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var canonicalHash: String {
        hash(of: Data(canonicalScript.utf8))
    }

/// MUST be kept byte-identical to `Scripts/claude-fuel-statusline.sh`.
    /// A mismatch is caught at runtime via the hash check above.
    static let canonicalScript: String = #"""
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
"""#
}
