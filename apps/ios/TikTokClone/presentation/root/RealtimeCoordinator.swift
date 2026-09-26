import Foundation

// Ouvre la connexion temps réel quand un compte est connecté et l'app au premier plan, la ferme sinon
// (l'app suspendue ne reçoit rien ; les notifications push prendront le relais), et distribue les événements
// aux écrans : fin du transcodage des publications, centre d'activité, messagerie.
@MainActor
final class RealtimeCoordinator {
    private let channel: any RealtimeChannel
    private let publishing: PublishingModel
    private let activity: ActivityModel
    private let messaging: MessagingModel
    private var wantsConnection = false
    // Connexions et déconnexions appliquées dans l'ordre.
    private var lastOperation: Task<Void, Never>?
    private var listener: Task<Void, Never>?

    init(channel: any RealtimeChannel, publishing: PublishingModel, activity: ActivityModel, messaging: MessagingModel) {
        self.channel = channel
        self.publishing = publishing
        self.activity = activity
        self.messaging = messaging
    }

    func update(signedIn: Bool, active: Bool) {
        startListening()
        let wanted = signedIn && active
        guard wanted != wantsConnection else { return }
        wantsConnection = wanted
        let previous = lastOperation
        lastOperation = Task { [channel] in
            await previous?.value
            if wanted { await channel.connect() } else { await channel.disconnect() }
        }
    }

    private func startListening() {
        guard listener == nil else { return }
        let updates = channel.updates
        listener = Task { [weak self] in
            for await update in updates {
                self?.handle(update)
            }
        }
    }

    private func handle(_ update: RealtimeUpdate) {
        switch update {
        case .connected:
            // Rien n'est rejoué : les événements manqués pendant la coupure sont relus par l'API REST.
            Task { await publishing.refresh() }
            Task { await activity.refresh() }
            Task { await messaging.refresh() }
        case .videoProcessed(let video):
            publishing.videoProcessed(video)
        case .notificationCreated(let notification, let unreadCount):
            activity.received(notification, unreadCount: unreadCount)
        case .unreadNotificationsChanged(let count):
            activity.unreadChanged(count)
        case .messageCreated, .messageDeleted, .conversationRead, .conversationAccepted, .conversationDeleted, .typing:
            messaging.handle(update)
        }
    }
}
