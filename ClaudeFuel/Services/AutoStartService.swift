import Foundation
import ServiceManagement

/// Wraps `SMAppService` for the launch-at-login toggle (FR-C1, FR-U3 General).
enum AutoStartService {
    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Best-effort: callers
    /// should re-read `isEnabled` to see what actually took effect.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort — the toggle reflects `isEnabled` on next read.
        }
    }
}
