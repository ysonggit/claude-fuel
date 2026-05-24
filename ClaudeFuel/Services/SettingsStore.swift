import Foundation

/// User-configurable settings. Usage values come from Claude Code's
/// status-line payload, so there is no local quota cap or calibration state.
struct Settings: Codable, Equatable {
    /// Launch at login via `SMAppService` (wired in a later milestone).
    var launchAtLogin: Bool = false
    /// Show only the gauge SF Symbol in the menu bar, no title (FR-U1).
    var iconOnlyMenuBar: Bool = false
    /// Show the island pill at the screen notch / top centre.
    var showIsland: Bool = false
}

/// Loads and persists `Settings` as JSON under Application Support (NFR 4.3).
/// Plain `Codable` + a single file — no Core Data / SwiftData (spec §5.1).
struct SettingsStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
        let dir = support.appending(path: "dev.ysong.claude-fuel",
                                    directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "settings.json")
    }

    /// Returns persisted settings, or freshly-defaulted settings if the file
    /// is absent or unreadable.
    func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
