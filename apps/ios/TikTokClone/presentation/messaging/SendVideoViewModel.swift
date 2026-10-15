import Foundation
import Observation

// « Envoyer par message » (action de la feuille de partage, choix du développeur) : la vidéo (ou le live en cours,
// ADR-053) est envoyée à un ou plusieurs comptes ou groupes (ADR-059), choisis parmi les conversations récentes puis les
// abonnements. L'API
// compte chaque envoi d'une vidéo comme un partage ; le compteur affiché suit.
@MainActor
@Observable
final class SendVideoViewModel {
    enum Delivery: Equatable {
        case sending
        case sent
    }

    // Destinataire possible : un compte (sa conversation, ouverte au besoin), ou un groupe (ADR-059).
    struct Recipient: Identifiable, Equatable {
        enum Target: Equatable {
            case user(UserSummary)
            case group(conversationID: String)
        }

        let target: Target
        // Nom affiché : le compte, ou le groupe (sinon les noms de ses membres).
        let title: String
        // Une photo, ou deux pour un groupe.
        let avatars: [UserSummary]

        init(user: UserSummary) {
            target = .user(user)
            title = user.displayName
            avatars = [user]
        }

        init(group conversation: Conversation, ownID: String?) {
            target = .group(conversationID: conversation.id)
            title = conversation.title(ownID: ownID)
            avatars = conversation.avatars(ownID: ownID)
        }

        var id: String {
            switch target {
            case .user(let user): user.id
            case .group(let conversationID): conversationID
            }
        }

        // Libellé d'accessibilité : « @bob », ou le nom du groupe.
        var label: String {
            switch target {
            case .user(let user): "@\(user.username)"
            case .group: title
            }
        }
    }

    // Ce qui est envoyé.
    enum Item: Equatable {
        case video(FeedVideo)
        case live(LiveStream)
    }

    let item: Item
    let following: PagedList<FollowEntry>
    private(set) var deliveries: [String: Delivery] = [:]
    var errorMessage: String?

    private let messaging: MessagingModel
    private let share: ShareVideoByMessageUseCase
    private let shareLive: ShareLiveByMessageUseCase?
    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    convenience init(
        video: FeedVideo,
        messaging: MessagingModel,
        loadFollows: LoadFollowsUseCase,
        share: ShareVideoByMessageUseCase,
        interactions: VideoInteractionsModel,
        session: SessionStore
    ) {
        self.init(
            item: .video(video), messaging: messaging, loadFollows: loadFollows, share: share, shareLive: nil, interactions: interactions,
            session: session)
    }

    init(
        item: Item,
        messaging: MessagingModel,
        loadFollows: LoadFollowsUseCase,
        share: ShareVideoByMessageUseCase,
        shareLive: ShareLiveByMessageUseCase?,
        interactions: VideoInteractionsModel,
        session: SessionStore
    ) {
        self.item = item
        self.shareLive = shareLive
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

    // Conversations récentes où l'on peut écrire, groupes compris.
    var recent: [Recipient] {
        let ownID = session.profile?.id
        return messaging.inbox.items.filter(\.canSend).compactMap { conversation in
            if conversation.isGroup { return Recipient(group: conversation, ownID: ownID) }
            return conversation.participant.map { Recipient(user: $0) }
        }
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
            switch (item, recipient.target) {
            case (.video(let video), .user(let user)):
                _ = try await share(videoID: video.id, to: user.username)
                interactions.sharedByMessage(video)
            case (.video(let video), .group(let conversationID)):
                _ = try await share(videoID: video.id, inConversation: conversationID)
                interactions.sharedByMessage(video)
            case (.live(let live), .user(let user)):
                guard let shareLive else { throw AppError.unexpected }
                _ = try await shareLive(liveID: live.id, to: user.username)
            case (.live(let live), .group(let conversationID)):
                guard let shareLive else { throw AppError.unexpected }
                _ = try await shareLive(liveID: live.id, inConversation: conversationID)
            }
            deliveries[recipient.id] = .sent
        } catch {
            deliveries[recipient.id] = nil
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() } else { errorMessage = error.message }
        }
    }
}
