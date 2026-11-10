import Foundation
import UserNotifications

/// Delivers native macOS notifications for authentication expirations and sync failures.
@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()

    private var notifiedAuthRemotes: Set<String> = []
    private var hasRequestedPermission: Bool = false
    public var onOpenManagerRequested: (() -> Void)?

    private var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private override init() {
        super.init()
        if isBundledApp {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    public func requestPermissionIfNeeded() {
        guard isBundledApp, !hasRequestedPermission else { return }
        hasRequestedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func notifyAuthExpired(remoteName: String) {
        guard isBundledApp else { return }
        guard !notifiedAuthRemotes.contains(remoteName) else { return }
        notifiedAuthRemotes.insert(remoteName)

        let content = UNMutableNotificationContent()
        content.title = "Google Drive Reconnection Needed"
        content.body = "Authorization for '\(remoteName)' expired. Open SyncTop to reconnect in your browser."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "synctop.auth.\(remoteName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func clearAuthNotification(for remoteName: String) {
        notifiedAuthRemotes.remove(remoteName)
        guard isBundledApp else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["synctop.auth.\(remoteName)"])
    }

    public func notifySyncFailed(profileId: UUID, profileName: String, reason: String) {
        guard isBundledApp else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sync Failed: \(profileName)"
        content.body = reason
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "synctop.fail.\(profileId.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.onOpenManagerRequested?()
        }
        completionHandler()
    }
}
