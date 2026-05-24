import Foundation
import UserNotifications

/// Delivers the fresh-chat suggestion as a system notification and tracks the
/// rate-limit and dismissal state behind it (FR-N1).
///
/// `@MainActor` because it doubles as the `UNUserNotificationCenter` delegate
/// and feeds dismissal state back to `AppState`.
@MainActor
final class NotificationService: NSObject {
    private static let categoryID = "fresh-chat"
    private static let dismissActionID = "fresh-chat.dismiss"
    private static let identifierPrefix = "fresh-chat-"
    /// No more than one notification globally within this interval (FR-N1).
    private static let globalCooldown: TimeInterval = 30 * 60

    /// Sessions that already received a notification — max one per session.
    private var deliveredSessions: Set<String> = []
    /// Sessions the user silenced via the notification's action button.
    private var dismissedSessions: Set<String> = []
    private var lastDelivered: Date?
    private var permissionResolved = false
    private var permissionGranted = false

    /// True when the popover banner for `sessionId` should stay hidden because
    /// the user tapped "Don't suggest again this session".
    func isDismissed(_ sessionId: String) -> Bool {
        dismissedSessions.contains(sessionId)
    }

    /// Installs the delegate and the notification category/action. Call once
    /// at startup.
    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let dismiss = UNNotificationAction(
            identifier: Self.dismissActionID,
            title: "Don't suggest again this session"
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [dismiss],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    /// Delivers a fresh-chat notification for `sessionId` if the per-session
    /// and global rate limits allow it (FR-N1). Permission is requested lazily
    /// on the first qualifying trigger.
    func notifyFreshChat(sessionId: String) async {
        guard !deliveredSessions.contains(sessionId),
              !dismissedSessions.contains(sessionId)
        else { return }
        if let last = lastDelivered,
           Date().timeIntervalSince(last) < Self.globalCooldown { return }
        guard await ensurePermission() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for a fresh chat"
        content.body = "This session's turns are getting expensive — a new one will run leaner."
        content.categoryIdentifier = Self.categoryID

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + sessionId,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            deliveredSessions.insert(sessionId)
            lastDelivered = Date()
        } catch {
            // Delivery failed (e.g. permission revoked) — leave state untouched
            // so a later trigger can retry.
        }
    }

    /// Requests authorization once, on first use (FR-N1).
    private func ensurePermission() async -> Bool {
        if permissionResolved { return permissionGranted }
        permissionResolved = true
        permissionGranted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        return permissionGranted
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Show the banner even though the app runs as a foreground agent.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Records the user's "don't suggest again this session" choice.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.dismissActionID else { return }
        let id = response.notification.request.identifier
        guard id.hasPrefix(Self.identifierPrefix) else { return }
        dismissedSessions.insert(String(id.dropFirst(Self.identifierPrefix.count)))
    }
}
