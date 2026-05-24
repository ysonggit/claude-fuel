import SwiftUI

/// Tabbed settings window (FR-U3). v0.2 ships the General and Data tabs;
/// Notifications and About arrive in v0.3 (spec §7).
struct SettingsRoot: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DataTab()
                .tabItem { Label("Data", systemImage: "doc.text.magnifyingglass") }
        }
        .frame(width: 440, height: 420)
    }
}
