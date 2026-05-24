import AppKit
import SwiftUI

/// Hosts the SwiftUI settings UI in a directly-managed AppKit window.
///
/// A menu-bar agent app (`LSUIElement`) can't reliably surface SwiftUI's
/// `Settings` scene — `SettingsLink` / `showSettingsWindow:` frequently open
/// the window behind everything or not at all. Managing an `NSWindow`
/// ourselves and calling `activate()` + `makeKeyAndOrderFront` is reliable.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// Creates the window on first use, then brings it (and the app) forward.
    func show(appState: AppState) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsRoot().environment(appState)
            )
            let win = NSWindow(contentViewController: hosting)
            win.title = "claude-fuel Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
