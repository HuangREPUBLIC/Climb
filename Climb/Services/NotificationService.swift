import Combine
import Foundation
import UserNotifications

enum NotificationService {
    /// Key the tapped-notification route reads the match id back out of.
    static let matchIDKey = "matchID"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Called after a sync completes. Prompts the player to reflect shortly
    /// after new matches are detected, per the proposal's "Reflection
    /// reminders" feature.
    static func scheduleReflectionReminder(
        newMatchCount: Int,
        matchID: String? = nil,
        championName: String? = nil
    ) {
        guard newMatchCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = newMatchCount == 1 ? "Match imported" : "\(newMatchCount) matches imported"
        // Naming the champion makes the reminder about a game the player
        // remembers, rather than about the app having done some work.
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

/// Routes a tapped notification to the match it was about.
///
/// Without this a tap just reopens the app on whatever tab it was last on, and
/// the player still has to go and find the game the reminder meant — which is
/// most of the work the reminder was supposed to save.
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// Held as state rather than delivered as an event: a cold launch from a
    /// notification runs this delegate before any view exists to receive it, so
    /// the id has to wait somewhere until the UI is ready to consume it.
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

    /// Reminders are worth showing while the app is open too — the player is
    /// usually looking at a different screen entirely when one fires.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
