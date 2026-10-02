import Foundation
import TikTokAPI

// Messages du serveur (`{ event, data }`), décodés avec les types générés depuis la spec (schéma `RealtimeEvent`),
// puis traduits en événements du domaine.
struct RealtimeEventDecoder: Sendable {
    // Nil pour un message illisible ou inconnu.
    func decode(_ text: String) -> RealtimeUpdate? {
        let decoder = JSONDecoder()
        // Dates ISO 8601 avec millisecondes, comme le client généré.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        guard let event = try? decoder.decode(Components.Schemas.RealtimeEvent.self, from: Data(text.utf8)) else { return nil }
        switch event {
        case .videoProcessed(let event):
            return .videoProcessed(OwnVideo(event.data))
        case .notificationCreated(let event):
            return .notificationCreated(ActivityNotification(event.data.notification), unreadCount: event.data.unreadCount)
        case .unreadNotificationsChanged(let event):
            return .unreadNotificationsChanged(event.data.unreadCount)
        case .messageCreated(let event):
            let data = event.data
            return .messageCreated(DirectMessage(data.message), badges(data.unreadConversations, data.pendingRequests))
        case .messageDeleted(let event):
            let data = event.data
            return .messageDeleted(
                conversationID: data.conversationId, messageID: data.messageId, badges(data.unreadConversations, data.pendingRequests))
        case .conversationRead(let event):
            let data = event.data
            return .conversationRead(
                conversationID: data.conversationId,
                readerID: data.readerId,
                lastReadMessageID: data.lastReadMessageId,
                badges(data.unreadConversations, data.pendingRequests)
            )
        case .conversationAccepted(let event):
            let data = event.data
            return .conversationAccepted(conversationID: data.conversationId, badges(data.unreadConversations, data.pendingRequests))
        case .conversationDeleted(let event):
            let data = event.data
            return .conversationDeleted(conversationID: data.conversationId, badges(data.unreadConversations, data.pendingRequests))
        case .typing(let event):
            return .typing(conversationID: event.data.conversationId, userID: event.data.userId)
        case .walletUpdated(let event):
            return .walletUpdated(balance: event.data.balance)
        }
    }

    private func badges(_ unreadConversations: Int, _ pendingRequests: Int) -> MessagingBadges {
        MessagingBadges(unreadConversations: unreadConversations, pendingRequests: pendingRequests)
    }
}

// Messages de l'app (schéma `RealtimeClientMessage`), encodés avec les types générés.
enum RealtimeClientMessageEncoder {
    static func typing(conversationID: String) -> String? {
        let message = Components.Schemas.RealtimeClientMessage.typing(.init(event: .typing, data: .init(conversationId: conversationID)))
        guard let data = try? JSONEncoder().encode(message) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
