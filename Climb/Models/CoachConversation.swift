import Foundation
import SwiftData

@Model
final class CoachConversation {
    var createdAt: Date
    var match: Match?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    init(createdAt: Date = .now, match: Match? = nil, messages: [ChatMessage] = []) {
        self.createdAt = createdAt
        self.match = match
        self.messages = messages
    }
}
