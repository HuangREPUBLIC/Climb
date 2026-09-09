import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case player
    case coach
}

@Model
final class ChatMessage {
    var role: ChatRole
    var text: String
    var timestamp: Date

    var conversation: CoachConversation?

    init(role: ChatRole, text: String, timestamp: Date = .now) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
