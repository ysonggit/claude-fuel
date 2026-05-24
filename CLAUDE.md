# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Repository status

**The repo is mid-implementation.** Everything below §1 is the v0.2 *requirements specification*. There is now a buildable, runnable Xcode project; a vertical slice works end-to-end.

- **Done & building** — `ClaudeFuel.xcodeproj` at the repo root builds and runs. All v0.2 in-scope behaviour (§7) is implemented: menu bar item, popover with state-of-charge + turn-curve chart + fresh-chat banner + daily summary, the General/Data settings tabs, one-click calibration, and the fresh-chat notification. Source: `ClaudeFuelApp.swift` (`@main`), `Models/` (`JSONLEntry`, `SessionCursor`, `Turn`, `WindowState`, `DailyState`, `AppState`), `Services/` (`JSONLScanner`, `Estimator`, `SuggestionEngine`, `SettingsStore`, `JSONLWatcher`, `NotificationService`, `AutoStartService`), `Utilities/`, `Views/` (+ `Views/Settings/`). `Estimator`/`SuggestionEngine`/scanner remain SwiftUI-free and unit-testable.
- **Design system** — `DesignSystem/` (`Colors`, `Typography`, `Spacing`) implements the `design/preview.html` mockup: terracotta/paper palette with light+dark adaptation, hairline-ruled sections, bordered stat cards. `PopoverView` and `TurnCurveView` are themed; the Settings window keeps native macOS `Form` styling by design.
- **Not yet built** — any tests.
- **Naming gotcha** — the settings model struct is `Settings` (`SettingsStore.swift`), which collides with SwiftUI's `Settings` scene; `ClaudeFuelApp.swift` therefore qualifies the scene as `SwiftUI.Settings`.
- **Fonts** — the preview specifies Source Serif 4 + Inter; `Typography.swift` currently uses the system serif (New York) and SF as close stand-ins. Bundling the real fonts under `Resources/Fonts/` is still open.

Build commands:
- `xcodebuild -project ClaudeFuel.xcodeproj -scheme ClaudeFuel -configuration Debug build`
- Tests (once a test target exists): `xcodebuild -project ClaudeFuel.xcodeproj -scheme ClaudeFuel test`, single test via `-only-testing:ClaudeFuelTests/<Class>/<method>`.

Deviations from the spec — behavioural:
- **Fixed-block window, not rolling (FR-S1).** Claude meters its session limit in fixed 5h blocks; `Estimator.windowState` finds the current block (first activity, advancing every time a record lands past `blockStart + 5h`) and sums from there. The spec's rolling "oldest entry + 5h" model diverged from Claude's real reset time.
- **Percentage calibration (FR-C2).** The JSONL cannot yield Claude's true limit denominator — `cache_read` tokens dominate the weighted sum (often 10–20M in a block), so any fixed cap is a guess. `AppState.calibrate(observedPercentUsed:)` instead back-computes the cap from a `% used` figure the user reads off Claude's own usage screen. Until calibrated, "% left" is not trustworthy.

Deviations from the spec, accepted to keep the slice runnable:
- **Deployment target is macOS 14, not 13.** The spec (§4.4, §6.3) chose macOS 13, but §5.3's mandated `@Observable` (Observation macro) requires macOS 14. Revisit if macOS 13 support is reaffirmed — it would mean dropping `@Observable` for `ObservableObject`.
- The project uses an Xcode-generated `PBXFileSystemSynchronizedRootGroup` (synchronized folder) — new `.swift` files added under `ClaudeFuel/` are picked up automatically; no `.pbxproj` edit needed.
- App sandbox is **off** (`ENABLE_APP_SANDBOX = NO`) — required to read `~/.claude/projects/` (§6.4).

v0.1 Tauri/Rust/Chrome-extension artifacts referenced in §5.6 are already gone — do not look for them.

### Conventions established by the existing core

The implemented `Services/`/`Models/` set the patterns the rest of the app should follow:
- **Pure, deterministic computation**: `Estimator` and `SuggestionEngine` are stateless `enum`s whose functions take all inputs — including `now: Date` — explicitly. Keep new computation logic in this style so it stays unit-testable without a clock.
- **`UsageRecord` is the flattened currency**: `JSONLScanner` decodes raw `JSONLEntry` lines, deduplicates by `message.id`, and emits `[UsageRecord]`. Everything downstream (`Estimator`, views) consumes `UsageRecord`/`ScanResult`, never raw `JSONLEntry`.
- **Lenient decoding**: missing JSONL subfields decode to zero, malformed lines are skipped — never crash parsing (NFR 4.2). Preserve this when extending the schema.
- **`JSONLScanner` is an `actor`** holding cross-scan state (`records`, `cursors`); `AppState` will be `@MainActor`. Respect these isolation domains when wiring the watcher → scanner → state → views data flow (§5.3).

---

# claude-fuel · v0.2 Requirements (Swift / macOS)

> **Platform pivot**: From cross-platform Tauri to **macOS-native SwiftUI**. The product is now a single-platform, single-language application built with the best tools Apple provides. We accept a narrower audience in exchange for material gains in design fidelity, performance, and "feels like a 1st-party tool" perception.

---

## 1. Background & Decision Context

### 1.1 What changed since v0.1

| Dimension | v0.1 | v0.2 |
|---|---|---|
| Architecture | Chrome extension + Tauri menu-bar app | Single SwiftUI macOS app |
| Data source | DOM scraping on claude.ai | Local Claude Code JSONL transcripts |
| Token counts | Estimated (chars/3.8, ±10–15%) | Real (from `message.usage` field) |
| Target audience | claude.ai web users | Claude Code Pro/Max subscribers |
| Platform | macOS, Windows, Linux | macOS only |

### 1.2 Why macOS-only Swift

**Audience reality**: Claude Code Pro/Max subscribers skew heavily macOS (developer demographics + Apple Silicon performance for AI workflows). Windows/Linux subset is small enough that supporting it costs more in quality than it returns in coverage.

**Design fidelity**: The product's differentiation rests on feeling Claude-native — Source Serif 4 type, terracotta accent, precise spacing, fluid SwiftUI popovers. WebView-rendered UIs are visibly second-rate on macOS to the audience we want to win.

**Footprint**: Native binary ~3–5MB, ~30–50MB memory, <100ms cold start. Critical for an always-running menu bar app — Tauri's 80–150MB memory is a deal-breaker for a tool meant to live in your menu bar forever.

**OS integration**: Real `NSPopover` (not a faux popover window), real `NSStatusItem`, real `UNUserNotificationCenter` notifications with actions, real `SMAppService` autostart, SF Symbols, system-aware light/dark adaptation. None of these are properly available through Tauri.

### 1.3 Trade-offs accepted
- **Windows/Linux users excluded** in v0.2. Possible v0.3 if demand materializes.
- **Higher initial dev cost** (2–3 weeks vs. 3–5 days) — accepted as investment in quality
- **No code sharing with future projects** in other languages — accepted

---

## 2. Product Definition

### 2.1 One-line description
A native macOS menu-bar companion for Claude Code that reads your local session transcripts, shows live token usage and 5-hour window remaining, and suggests when to start a fresh session before context rot makes it expensive.

### 2.2 Primary user
A Claude Code Pro or Max subscriber on macOS who:
- Runs `claude` (the CLI) regularly on their machine
- Has experienced rate-limit anxiety or unexpected limit hits
- Values lightweight, always-visible tooling over dashboards
- Notices and cares about native macOS feel

### 2.3 Non-goals (explicit)
- ❌ Not a usage tracker for claude.ai web users (no JSONL → no path)
- ❌ Not a Windows or Linux app in v0.2
- ❌ Not a billing/cost calculator
- ❌ Not a transcript viewer (lm-assist, claude-code-log exist)
- ❌ Not a CLI tool (ccusage exists)
- ❌ Not a team/org analytics tool

### 2.4 Differentiation
1. **Native macOS menu-bar form factor** — fluid, light, always visible
2. **"It's time to start a fresh chat" behavioral nudge** with native notification
3. **Calibrated to Claude's design language** via SwiftUI Source Serif 4 + terracotta system
4. **Honest about JSONL quality** — visible confidence indicator instead of false precision

---

## 3. Functional Requirements

### 3.1 Data acquisition

**FR-D1 — Discover JSONL files**
- Primary location: `~/.claude/projects/`
- Fallback location: `~/.config/claude/projects/`
- Use `FileManager.default` with `.homeDirectoryForCurrentUser`
- If neither exists, present empty state with onboarding text

**FR-D2 — Parse JSONL incrementally**
- Stream file line-by-line (do NOT load entire JSONL into memory)
- Parse each line with `JSONDecoder` into a `JSONLEntry` struct (see §5.4)
- Skip lines where `type != "assistant"` or `message.usage` is missing
- Track last-read byte offset per session (`SessionCursor`) so subsequent scans are O(new bytes)

**FR-D3 — Deduplicate by request ID**
- Multiple entries may share `message.id` (= request ID)
- Collapse to one: keep entry with **largest** `output_tokens` (streaming entries grow)
- This addresses the [JSONL 10–100× undercount issue](https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/) that affects all naive parsers

**FR-D4 — Identify the active session**
- "Active" = JSONL file modified within last 30 minutes
- If multiple are active, pick most recently modified
- If none active, use most recent any-time session for "latest session" display

**FR-D5 — File watching**
- Use `DispatchSource.makeFileSystemObjectSource` on the projects directory(ies)
- Watch flags: `.write`, `.extend`, `.rename`, `.delete`
- Debounce events: 500ms coalescing window
- Fallback: 10s polling timer if dispatch source fails to attach
- Per-file watchers only for currently-active session (to bound watcher count)

### 3.2 State computation

**FR-S1 — Rolling 5-hour window**
- Sum all (deduplicated) `input_tokens + output_tokens + cache_creation_input_tokens` for entries with timestamp in last 5 hours
- `cache_read_input_tokens` counted at 0.1× weight
- Window reset countdown = `(oldest_in_window_timestamp + 5h) − now`
- Display: tokens used, % of configured cap, time until oldest-rolls-off

**FR-S2 — Daily usage**
- Two values:
  - Last 24 hours (rolling)
  - Calendar today (local timezone, midnight to now)
- Both shown — answer different questions ("how much today?" vs. "how much last day?")

**FR-S3 — Per-session cost curve**
- For active session, compute marginal cost per turn
- "Turn" = one user message + the assistant response(s) until next user message
- Marginal cost = sum of all prior turn tokens + this turn's new tokens
- Output: `[Turn]` array consumed by chart view (see FR-U2)

**FR-S4 — Fresh-chat suggestion**
Trigger when ALL true:
- Active session has ≥8 turns
- Latest turn's marginal cost ≥ 3× the first turn's
- Latest turn ≥ 3,000 tokens absolute
- Surface as: macOS notification (FR-N1) + banner in popover

**FR-S5 — Confidence indicator**
- HIGH: ≥80% of assistant entries have `input_tokens > 1` (not streaming placeholder)
- MEDIUM: 40–80%
- LOW: <40%
- Displayed in popover footer; settings panel explains what it means

### 3.3 User interface

**FR-U1 — Menu bar status item**
- Use `NSStatusBar.system.statusItem(withLength: .variable)` or SwiftUI `MenuBarExtra`
- Title format: `<pct>% · <time-to-reset>` (e.g., `62% · 2h47m`)
- Use system font, **monospaced digits** variant
- Visual states:
  - ≥50% remaining: default appearance
  - 20–50%: subtle SF Symbol prefix `⏳`
  - <20%: SF Symbol prefix `⚠︎`, slightly emphasized
  - Stale (>10 min idle): suffix `·zz` in lower opacity
- Width target: ≤14 characters to play nice with other status items
- Icon-only mode (optional, settings toggle): SF Symbol `gauge.medium` only, no title

**FR-U2 — Popover**
- Real `NSPopover` (not a window), `behavior = .transient` (closes on outside click)
- Size: 380×~560pt, adapts to content (no scrollbar, no resize handles)
- Animates in/out per macOS norms
- Sections (top to bottom):
  1. **Header**: wordmark, live/stale indicator
  2. **State of charge**: large %, reset time, key stats row group
  3. **Active session curve** (if ≥2 turns): mini bar chart (SwiftUI `Canvas` or `Path`)
  4. **Fresh-chat suggestion banner** (conditional, FR-S4)
  5. **Daily summary**: today's tokens + last-24h
  6. **Footer**: confidence indicator, settings gear, quit

**FR-U3 — Settings window**
- Separate window (not popover), opened via gear icon or right-click menu
- Use SwiftUI `Settings` scene API (macOS 13+) with `TabView`
- Tabs:
  - **General**: window cap, daily soft budget, autostart toggle
  - **Notifications**: enable/disable each notification class
  - **Data**: list of detected JSONL paths, "Calibrate from current window" button, export, clear cache
  - **About**: version, license, links

**FR-U4 — Empty state**
- Shown when no JSONL found OR all sessions show 0 valid entries
- Content: "Install Claude Code to get started", brief 3-step quickstart, link to docs
- No fake data, no preview-mode

**FR-U5 — Stale state**
- Newest JSONL untouched >30 min
- Header indicator dims; menu bar title adds `·zz`
- Settings → Data tab shows "last activity: X ago"

### 3.4 Notifications

**FR-N1 — Fresh-chat suggestion**
- `UNUserNotificationCenter` notification
- Action button: "Don't suggest again this session"
- Rate-limit: max one per session, max one per 30 min globally
- Permission requested on first qualifying trigger, with in-popover explanation if denied

**FR-N2 — Window depletion warning** (v0.3)
**FR-N3 — Daily budget breach** (v0.3)

### 3.5 Calibration

**FR-C1 — Defaults**
- Window cap: **220,000 tokens** (conservative for Pro)
- Daily budget: unset (opt-in)

**FR-C2 — One-click calibration**
- Settings → Data → "Calibrate from current window"
- Sets `windowTokenCap = current observed tokens in last 5h`
- Disabled if observed <5,000 tokens (no signal to calibrate from)
- Confirmation sheet: "Use this only after Claude Code reported a limit hit"

---

## 4. Non-Functional Requirements

### 4.1 Performance
- Initial JSONL scan: <2s for typical user (≤200MB total transcripts)
- Steady-state CPU: <1% on Apple Silicon, <2% on Intel
- Memory: <50MB resident
- Popover open-to-render: <50ms (data pre-computed in memory)
- Cold launch to menu bar item visible: <300ms

### 4.2 Reliability
- Malformed JSONL lines silently skipped, never crash parsing
- File watcher failure → fall back to 10s polling, log warning
- Unknown JSONL fields ignored (forward-compatible with Claude Code updates)
- Missing `usage` subfields treated as zero, not nil-crash

### 4.3 Privacy
- Fully local: no telemetry, no analytics, no crash reporting service
- Read JSONL `usage`, timestamps, IDs, model names ONLY — never message content text
- Settings export excludes any content
- Config storage: `~/Library/Application Support/dev.ysong.claude-fuel/`
- All app data deletable via Settings → Data → Clear All

### 4.4 Platform
- **macOS 13 (Ventura) minimum** — enables `MenuBarExtra` SwiftUI API and `Settings` scene
- **Universal binary**: arm64 + x86_64
- Tested on macOS 13, 14, 15 across both architectures

### 4.5 Distribution
- GitHub Releases as primary channel
- Format: `.dmg` containing `.app`
- **Ad-hoc signed** for v0.2 (Developer ID + notarization deferred to v0.3 if needed)
- Homebrew Cask submission planned post-launch
- No Mac App Store in v0.2 (sandbox restrictions on reading `~/.claude/` are awkward)

---

## 5. Architecture

### 5.1 Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (primary) + AppKit (`NSStatusItem`, `NSPopover` bridging where SwiftUI APIs are insufficient)
- **Async**: Swift Concurrency (`async`/`await`, `AsyncStream`, actors)
- **Persistence**: Plain `Codable` + JSON file in Application Support (no Core Data, no SwiftData — overkill for our data volume)
- **Build**: Xcode project (no SwiftPM-only build — we need bundle resources and Info.plist)
- **Dependencies**: NONE in v0.2 — all native frameworks (Foundation, SwiftUI, AppKit, UserNotifications, ServiceManagement, CoreServices)

### 5.2 Module layout (Xcode groups)

```
ClaudeFuel/
├── ClaudeFuelApp.swift                # @main, App scene + MenuBarExtra
├── Resources/
│   ├── Assets.xcassets/                # AppIcon, MenuBarIcon (template)
│   ├── Fonts/                          # Source Serif 4 (subsetted), Inter
│   └── Info.plist                      # LSUIElement = YES
│
├── Models/
│   ├── JSONLEntry.swift                # Decodable schema for one JSONL line
│   ├── SessionCursor.swift             # Last-read offset per session file
│   ├── Turn.swift                      # User+assistant pair with token totals
│   ├── WindowState.swift               # 5h rolling window aggregate
│   ├── DailyState.swift                # 24h and calendar-today aggregates
│   └── AppState.swift                  # Top-level observable state object
│
├── Services/
│   ├── JSONLScanner.swift              # File discovery + incremental parsing + dedup
│   ├── JSONLWatcher.swift              # DispatchSource-based file watching
│   ├── Estimator.swift                 # WindowState/DailyState/Turn computation
│   ├── SuggestionEngine.swift          # Fresh-chat trigger logic
│   ├── NotificationService.swift       # UNUserNotificationCenter wrapper
│   ├── AutoStartService.swift          # SMAppService wrapper for login-item
│   └── SettingsStore.swift             # Codable settings persistence
│
├── Views/
│   ├── MenuBarTitleView.swift          # Renders status item title
│   ├── PopoverView.swift               # Root popover content
│   ├── Popover/
│   │   ├── HeaderView.swift
│   │   ├── StateOfChargeView.swift
│   │   ├── TurnCurveView.swift         # SwiftUI Path-based mini chart
│   │   ├── SuggestionBannerView.swift
│   │   ├── DailySummaryView.swift
│   │   └── FooterView.swift
│   ├── Settings/
│   │   ├── SettingsRoot.swift          # TabView container
│   │   ├── GeneralTab.swift
│   │   ├── NotificationsTab.swift
│   │   ├── DataTab.swift
│   │   └── AboutTab.swift
│   └── EmptyStateView.swift
│
├── DesignSystem/
│   ├── Colors.swift                    # CFColors.paper, .terra, .ink, etc.
│   ├── Typography.swift                # CFType.serifTitle, .sansBody, etc.
│   ├── Spacing.swift
│   └── ViewModifiers.swift             # .cfEyebrow(), .cfStatRow(), etc.
│
└── Utilities/
    ├── DateFormatting.swift            # "2h 47m", "17:34", etc.
    ├── TokenFormatting.swift           # 5432 → "5.4k"
    └── DebouncedTask.swift             # Generic debouncer for watcher coalescing
```

### 5.3 Data flow

```
~/.claude/projects/ JSONL files
        │
        ▼  (DispatchSource events, debounced 500ms)
JSONLWatcher  ──events──▶  JSONLScanner.scanChanged()
                                  │
                                  ▼
                            Estimator.recompute()
                                  │
                                  ▼  @Published
                              AppState
                                  │
        ┌─────────────────────────┼─────────────────────────────┐
        ▼                         ▼                             ▼
  MenuBarTitleView          PopoverView                NotificationService
  (status item title)       (when open)                (when SuggestionEngine fires)
```

`AppState` is an `@Observable` (Swift 5.9+ Observation macro) class. SwiftUI views observe it directly; updates flow via SwiftUI's tracking. No Combine pipelines, no manual notification posts.

### 5.4 Key model: JSONLEntry

```swift
struct JSONLEntry: Decodable {
    let type: String                   // "assistant", "user", "summary", ...
    let timestamp: Date
    let sessionId: String
    let message: Message?

    struct Message: Decodable {
        let id: String?                // request ID, used for dedup
        let role: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
```

### 5.5 Concurrency model

- **Watcher**: dedicated `DispatchQueue(label: "claude-fuel.watcher")` for file system events
- **Scanner**: `actor JSONLScanner` — serializes parsing, prevents concurrent reads of the same file
- **AppState**: `@MainActor` — all UI-observable state updates on the main actor
- **Suggestion engine**: pure functions, called from AppState setters; notifications dispatched async

### 5.6 What's removed from v0.1 / v0.2-Rust

Everything Tauri- or Rust- or Chrome-extension-related is dropped. Specifically:
- `claude-fuel-menubar/src-tauri/` (entire Rust project)
- `claude-fuel/` (entire Chrome extension)
- `axum`, `tokio`, `serde_json` Rust deps
- All HTML/JS/CSS for popover (will be re-implemented in SwiftUI using same design tokens)

### 5.7 What's salvaged

- **Design tokens** (`tokens.css` palette → `Colors.swift` + `Typography.swift`)
- **v3 mockup as visual reference** for SwiftUI layout
- **Estimator logic** (JS → Swift port; well-tested unit logic is independent of language)
- **README structure and "honest estimator" framing**
- **Icon assets** (placeholder PNGs replaced with proper macOS App Icon set)

---

## 6. Open Questions & Known Risks

### 6.1 Anthropic ships `claude usage` officially
Issue [anthropics/claude-code#33978](https://github.com/anthropics/claude-code/issues/33978) is a feature request for an official command. If/when shipped, raw data display is commoditized.

**Mitigation**: Differentiate on form factor (menu bar, always-visible) and behavioral nudges (fresh-chat suggestion), not on having access to data.

### 6.2 JSONL token undercount (documented industry-wide bug)
75% of entries can have placeholder `input_tokens` of 0 or 1. ccusage and similar tools underreport by 10–100×.

**Mitigation**:
- Implement `message.id` dedup (FR-D3)
- Surface confidence indicator (FR-S5)
- When confidence LOW, soften UI claims
- Document this in README — turn it into a credibility asset

### 6.3 macOS minimum version
Choosing macOS 13 unlocks `MenuBarExtra` SwiftUI API and `Settings` scene, but excludes macOS 11/12 users (~10–15% of active macOS install base as of 2026).

**Mitigation**: Accept the trade. macOS 13 lets us write 90% SwiftUI; older versions force a much heavier AppKit footprint. Power-user developer audience updates faster than general population.

### 6.4 Sandbox vs. file access
Reading `~/.claude/projects/` from a sandboxed app requires user file-access grant via `NSOpenPanel` (not transparent). Mac App Store would force sandboxing.

**Mitigation**: Ship outside the App Store. GitHub Releases + ad-hoc signing only. Document install steps including Gatekeeper bypass for unsigned/ad-hoc apps.

### 6.5 Multiple Claude Code sessions
User may have several `claude` processes writing to different JSONL files simultaneously. All count toward the same 5h rate limit.

**Mitigation**: Aggregation handles it (sum across all files). Active session for "current curve" display is just the most-recently-modified one.

### 6.6 Subagent token counts
Claude Code writes subagent activity to `subagents/` subdirectories.

**Mitigation**: Follow `#33978` proposed convention — skip `subagents/` for top-level usage. Reserve subagent breakdown for v0.3.

---

## 7. v0.2 Scope

### In scope
- All FR-D* (data acquisition)
- FR-S1 through FR-S5 (state computation)
- FR-U1, FR-U2, FR-U3 (General + Data tabs only), FR-U4, FR-U5
- FR-N1 (fresh-chat notification only)
- FR-C1, FR-C2 (defaults + one-click calibration)
- Universal binary, ad-hoc signed, GitHub Releases distribution
- README with installation, calibration, JSONL accuracy disclosure

### Out of scope (v0.3+)
- FR-N2, FR-N3 (depletion + budget notifications)
- Notifications tab in settings (UI for FR-N2/N3 toggles)
- Developer ID signing + notarization
- Mac App Store submission
- Per-project breakdown
- Cost-in-USD calculation
- Subagent token aggregation
- Windows/Linux ports
- Claude.ai web user support

---

## 8. Success Criteria

### 8.1 v0.2 release acceptance
- [ ] Fresh install reads existing JSONL and shows correct token counts within 5 seconds
- [ ] Menu bar updates within 5 seconds of new turn written to JSONL
- [ ] Popover opens with full content rendered in <50ms
- [ ] Empty state appears correctly when `~/.claude/projects/` absent
- [ ] Stale state appears correctly after 30 min inactivity
- [ ] Fresh-chat notification fires exactly once per qualifying session
- [ ] Settings → "Calibrate from current window" sets cap and persists across restart
- [ ] Confidence indicator drops to LOW when test data is dominated by streaming placeholders
- [ ] Quitting from menu bar tray exits cleanly, no orphan processes
- [ ] Universal binary runs on M-series and Intel Macs without rebuild
- [ ] 24-hour soak test: no crash, memory growth <10MB

### 8.2 Open-source traction (3 months post-launch)
- ≥500 GitHub stars
- ≥10 external contributors
- README's data-quality disclosure cited positively in at least one comparison piece
- Homebrew Cask accepted

---

## 9. Strategy Notes

### 9.1 Naming
"claude-fuel" retained — works for any Claude session context.

### 9.2 Positioning
- Hero line: *"A quiet meter for your Claude Code sessions."*
- Tagline: "Native, honest, always on."
- README opens with a screenshot of the popover in macOS dark mode + light mode, side by side.

### 9.3 Launch path
1. Internal dogfood (1 week, user only) — make sure 24h soak passes
2. Soft launch to `/r/ClaudeAI`, `/r/macapps`, and HN Show HN
3. Open dialog with ccusage maintainers (interop, link exchange)
4. Submit to `awesome-claude-code` and `awesome-mac` lists
5. Homebrew Cask submission once installer is stable

### 9.4 Long-term defensibility
- Form factor stickiness: menu bar users don't switch to CLIs
- Behavioral nudges (fresh-chat suggestion) build trust over time; the "tool that knew when I should stop" moment is the moat
- Native macOS look-and-feel is hard to clone with taste even if functionality is copied

---

## 10. Dev Setup

For anyone (including future-you) opening this repo cold:

```bash
# Requirements
- macOS 14+ recommended for dev (deploy target is 13)
- Xcode 15.0 or newer
- Apple Developer account NOT required for v0.2 (ad-hoc signing)

# First build
git clone <repo>
cd claude-fuel
open ClaudeFuel.xcodeproj
# Cmd-R to run

# Where it puts data
~/Library/Application Support/dev.ysong.claude-fuel/
  ├── settings.json
  ├── cursors.json      # per-session last-read byte offsets
  └── snapshot.json     # warm-start cache of last computed state
```
