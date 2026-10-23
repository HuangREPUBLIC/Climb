import Combine
import Foundation
import UserNotifications

enum NotificationService {
    static let matchIDKey = "matchID"

    /// Called after a sync: reminds the player to reflect shortly after new matches arrive.
    static func scheduleReflectionReminder(
        newMatchCount: Int,
        matchID: String? = nil,
        championName: String? = nil
    ) {
        guard newMatchCount > 0 else { return }

        // Asked in context, not at launch, so the system prompt lands next to a reason rather
        // than as a cold "Climb Would Like to Send You Notifications".
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = newMatchCount == 1 ? "Match imported" : "\(newMatchCount) matches imported"
        // Naming the champion ties the reminder to a game the player remembers.
        if newMatchCount == 1, let championName {
            content.body = "How did the \(championName) game go? Add a note while it's fresh."
        } else if newMatchCount == 1 {
            content.body = "Add a quick reflection note while it's fresh."
        } else {
            content.body = "Jot down what you noticed in your latest games."
        }
        content.sound = .default
        // Carried so a tap can open the match itself — see NotificationRouter.
        if let matchID {
            content.userInfo = [matchIDKey: matchID]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Routes a tapped notification to the match it was about, instead of reopening on the last tab.
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// State, not an event: a cold launch runs the delegate before any view exists to consume it.
    @Published var pendingMatchID: String?

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let matchID = response.notification.request.content.userInfo[NotificationService.matchIDKey] as? String
        Task { @MainActor in
            if let matchID { self.pendingMatchID = matchID }
            completionHandler()
        }
    }

    /// Shown while the app is open too: the player is usually on another screen when one fires.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
