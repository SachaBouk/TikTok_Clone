import Foundation
import TikTokAPI

// Messages du serveur (`{ event, data }`), décodés avec les types générés depuis la spec (schéma `RealtimeEvent`),
// puis traduits en événements du domaine.
struct RealtimeEventDecoder: Sendable {
    // Nil pour un message illisible, inconnu, ou pas encore utilisé par l'app.
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
        // Activité et messagerie : traduites avec leurs écrans.
        case .notificationCreated, .unreadNotificationsChanged, .messageCreated, .messageDeleted,
             .conversationRead, .conversationAccepted, .conversationDeleted, .typing:
            return nil
        }
    }
}
