import SwiftUI

/// App entry point. A pure menu-bar app — set `LSUIElement = YES` in
/// Info.plist so there is no Dock icon or main window (spec §5.2).
@main
struct ClaudeFuelApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(appState.menuBarTitle, systemImage: appState.menuBarSymbol) {
            PopoverView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
