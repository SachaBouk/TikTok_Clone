import Foundation

// Ouvre la connexion temps réel quand un compte est connecté et l'app au premier plan, la ferme sinon
// (l'app suspendue ne reçoit rien ; les notifications push prendront le relais), et distribue les événements
// aux écrans : fin du transcodage des publications (vidéos et stories), centre d'activité, messagerie, solde de jetons,
// compteurs du profil ; la rangée de stories est relue à chaque (re)connexion.
@MainActor
final class RealtimeCoordinator {
    private let channel: any RealtimeChannel
    private let publishing: PublishingModel
    private let activity: ActivityModel
    private let messaging: MessagingModel
    private let wallet: WalletModel
    private let stories: StoriesModel
    private let ownProfile: OwnProfileSync
    private var wantsConnection = false
    // Connexions et déconnexions appliquées dans l'ordre.
    private var lastOperation: Task<Void, Never>?
    private var listener: Task<Void, Never>?

    init(
        channel: any RealtimeChannel, publishing: PublishingModel, activity: ActivityModel, messaging: MessagingModel, wallet: WalletModel,
        stories: StoriesModel, ownProfile: OwnProfileSync
    ) {
        self.channel = channel
        self.publishing = publishing
        self.activity = activity
        self.messaging = messaging
        self.wallet = wallet
        self.stories = stories
        self.ownProfile = ownProfile
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
            Task { await wallet.refresh() }
            Task { await ownProfile.refresh() }
            Task { await stories.refresh() }
        case .videoProcessed(let video):
            publishing.videoProcessed(video)
        case .storyProcessed(let story):
            publishing.storyProcessed(story)
        case .notificationCreated(let notification, let unreadCount):
            activity.received(notification, unreadCount: unreadCount)
        case .unreadNotificationsChanged(let count):
            activity.unreadChanged(count)
        case .notificationsRemoved(let removed, let groups, let unreadCount):
            activity.removed(removed, groups: groups, unreadCount: unreadCount)
        case .messageCreated, .messageDeleted, .conversationRead, .conversationAccepted, .conversationDeleted, .typing:
            messaging.handle(update)
        case .profileCountersChanged(let followers, let following):
            ownProfile.countersChanged(followers: followers, following: following)
        case .walletUpdated(let balance, let earned):
            wallet.balanceChanged(balance, earned: earned)
        }
    }
}
