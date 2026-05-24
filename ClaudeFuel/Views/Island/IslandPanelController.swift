import AppKit
import SwiftUI

/// Renders claude-fuel usage data in the macOS notch area by placing a
/// non-activating overlay panel at the top of the screen. The panel's black
/// background merges visually with the physical notch; content is drawn in
/// the displayable pixels flanking the camera cutout, identified via
/// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
///
/// On non-notch / external displays the panel appears as a compact bar at
/// the top centre.
@MainActor
final class IslandPanelController {
    private var panel: NotchPanel?

    // MARK: - Public

    func show(appState: AppState) {
        if panel == nil {
            panel = makePanel(appState: appState)
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Panel creation

    private func makePanel(appState: AppState) -> NotchPanel {
        let screen = NSScreen.main
        let isNotched = Self.isNotched(screen)
        let panelSize = Self.panelSize(screen: screen, isNotched: isNotched)

        let p = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Use NSHostingView directly (not NSHostingController) — matches
        // open-vibe-island's approach and gives us full control over the
        // view hierarchy.
        let hostingView = NSHostingView(
            rootView: IslandContentView(isNotched: isNotched)
                .environment(appState)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        p.contentView = hostingView

        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.level = .statusBar
        p.sharingType = .readOnly
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = false
        p.ignoresMouseEvents = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.collectionBehavior = [
            .fullScreenAuxiliary,
            .canJoinAllSpaces,
            .ignoresCycle,
            .stationary,
        ]

        return p
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let isNotched = Self.isNotched(screen)
        let size = Self.panelSize(screen: screen, isNotched: isNotched)

        // Centred horizontally, flush with the top of the screen.
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height

        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true
        )
    }

    // MARK: - Screen helpers

    private static func isNotched(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return screen.safeAreaInsets.top > 0
            || screen.auxiliaryTopLeftArea != nil
            || screen.auxiliaryTopRightArea != nil
    }

    /// Compute the notch width from the gap between the two auxiliary top areas.
    /// Falls back to 180pt if the API doesn't provide the info.
    private static func notchWidth(screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Notch = screen width minus the two flanking areas.
            return screen.frame.width - left.width - right.width
        }
        return 180 // safe default for 14"/16" MBP
    }

    /// Panel size: matches the physical notch width exactly.
    private static func panelSize(screen: NSScreen?, isNotched: Bool) -> NSSize {
        guard let screen else { return NSSize(width: 200, height: 50) }
        let notchHeight = screen.safeAreaInsets.top
        let width: CGFloat = isNotched ? notchWidth(screen: screen) : 200
        let height: CGFloat = isNotched ? notchHeight + 22 : 50
        return NSSize(width: width, height: height)
    }
}

// MARK: - NotchPanel subclass

/// Minimal NSPanel subclass matching open-vibe-island's NotchPanel.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
