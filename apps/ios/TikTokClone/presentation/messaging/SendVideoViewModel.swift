import Foundation
import Observation

// « Envoyer par message » (action de la feuille de partage, choix du développeur) : la vidéo est envoyée à un
// ou plusieurs comptes, choisis parmi les conversations récentes puis les abonnements. L'API compte chaque
// envoi comme un partage ; le compteur affiché suit.
@MainActor
@Observable
final class SendVideoViewModel {
    enum Delivery: Equatable {
        case sending
        case sent
    }

    // Destinataire possible : un compte, avec sa conversation s'il y en a une.
    struct Recipient: Identifiable, Equatable {
        let user: UserSummary
        var id: String { user.id }
    }

    let video: FeedVideo
    let following: PagedList<FollowEntry>
    private(set) var deliveries: [String: Delivery] = [:]
    var errorMessage: String?

    private let messaging: MessagingModel
    private let share: ShareVideoByMessageUseCase
    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    init(
        video: FeedVideo,
        messaging: MessagingModel,
        loadFollows: LoadFollowsUseCase,
        share: ShareVideoByMessageUseCase,
        interactions: VideoInteractionsModel,
        session: SessionStore
    ) {
        self.video = video
        self.messaging = messaging
        self.share = share
        self.interactions = interactions
        self.session = session
        let username = session.profile?.username
        following = PagedList(session: session) { cursor in
            guard let username else { return ([], nil) }
            let page = try await loadFollows(.following, username: username, cursor: cursor)
            return (page.entries, page.nextCursor)
        }
    }

    // Conversations récentes où l'on peut écrire.
    var recent: [Recipient] {
        messaging.inbox.items.filter(\.canSend).map { Recipient(user: $0.participant) }
    }

    // Abonnements, sans ceux déjà proposés parmi les conversations récentes.
    var others: [Recipient] {
        let recentIDs = Set(recent.map(\.id))
        return following.items.map { Recipient(user: $0.user) }.filter { !recentIDs.contains($0.id) }
    }

    func load() async {
        await messaging.inbox.loadFirstIfNeeded()
        await following.loadFirstIfNeeded()
    }

    func send(to recipient: Recipient) async {
        guard deliveries[recipient.id] == nil else { return }
        deliveries[recipient.id] = .sending
        do {
            _ = try await share(videoID: video.id, to: recipient.user.username)
            deliveries[recipient.id] = .sent
            interactions.sharedByMessage(video)
        } catch {
            deliveries[recipient.id] = nil
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() } else { errorMessage = error.message }
        }
    }
}
