import Foundation
import Observation

// « Envoyer par message » (feuille « Envoyer à », choix du développeur) : la vidéo (ou le live en cours, ADR-053) est
// envoyée à un ou plusieurs comptes ou groupes (ADR-059), choisis parmi les conversations récentes puis les abonnements.
// Feuille d'une vidéo, comme TikTok : les destinataires sont d'abord **choisis** (`toggle`), puis « Envoyer » part vers
// chacun avec le message facultatif (`sendSelected`, un seul message vidéo + texte) ; la loupe ouvre la liste complète
// (`sections`) et la recherche (`searchResults`). Le live garde un envoi par ligne (`send(to:)`). L'API compte chaque envoi
// d'une vidéo comme un partage ; le compteur affiché suit.
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
        // Nombre de membres d'un groupe (« 3 membres »).
        let memberCount: Int?

        init(user: UserSummary) {
            target = .user(user)
            title = user.displayName
            avatars = [user]
            memberCount = nil
        }

        init(group conversation: Conversation, ownID: String?) {
            target = .group(conversationID: conversation.id)
            title = conversation.title(ownID: ownID)
            avatars = conversation.avatars(ownID: ownID)
            memberCount = conversation.group?.members.count
        }

        var username: String? {
            if case .user(let user) = target { return user.username }
            return nil
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

    // Section de la liste complète : « Chats récents », « Amis », puis une par lettre sous « Suivis ».
    struct Section: Identifiable, Equatable {
        enum Kind: Equatable {
            case recent, friends
            case letter(String)
        }

        let kind: Kind
        let recipients: [Recipient]

        var id: String {
            switch kind {
            case .recent: "recent"
            case .friends: "friends"
            case .letter(let letter): "letter-\(letter)"
            }
        }
    }

    let item: Item
    let following: PagedList<FollowEntry>
    private(set) var deliveries: [String: Delivery] = [:]
    var errorMessage: String?
    // Destinataires choisis, dans l'ordre des touchers.
    private(set) var selected: [Recipient] = []
    // Message envoyé avec la vidéo (facultatif).
    var message = ""
    // Recherche de la liste complète.
    var query = ""
    private(set) var isSending = false
    // Tous les abonnements ont été lus (liste complète).
    private(set) var hasLoadedAllFollowing = false
    // Identifiant d'envoi par destinataire (ADR-044), gardé pour un nouvel essai après un échec.
    private var clientMessageIDs: [String: String] = [:]

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

    // MARK: Sélection et message

    func isSelected(_ recipient: Recipient) -> Bool { selected.contains { $0.id == recipient.id } }

    func toggle(_ recipient: Recipient) {
        guard !isSending else { return }
        if let index = selected.firstIndex(where: { $0.id == recipient.id }) {
            selected.remove(at: index)
        } else {
            selected.append(recipient)
        }
    }

    func appendEmoji(_ emoji: String) {
        guard message.count + emoji.count <= MessageRules.maxLength else { return }
        message += emoji
    }

    var canSendSelected: Bool { !selected.isEmpty && !isSending && message.count <= MessageRules.maxLength }

    // Envoie la vidéo, avec le message, à chaque destinataire choisi. Vrai si tout est parti ; sinon les destinataires
    // en échec restent choisis (message gardé) pour réessayer, avec le même identifiant d'envoi.
    @discardableResult
    func sendSelected() async -> Bool {
        guard canSendSelected else { return false }
        isSending = true
        defer { isSending = false }
        let text = MessageRules.cleaned(message)
        var failed: [Recipient] = []
        var lastError: AppError?
        for recipient in selected {
            let clientID = clientMessageIDs[recipient.id] ?? UUID().uuidString.lowercased()
            clientMessageIDs[recipient.id] = clientID
            deliveries[recipient.id] = .sending
            do {
                try await deliver(to: recipient, message: text, clientMessageID: clientID)
                deliveries[recipient.id] = .sent
                clientMessageIDs[recipient.id] = nil
            } catch {
                deliveries[recipient.id] = nil
                failed.append(recipient)
                lastError = AppError.from(error)
                if lastError == .sessionExpired { break }
            }
        }
        if let lastError {
            // Session expirée : le reste n'est pas tenté.
            if lastError == .sessionExpired {
                session.sessionExpired()
                return false
            }
            selected = failed
            errorMessage = failed.count == 1 ? lastError.message : "Envoi impossible à \(failed.count) destinataires. \(lastError.message)"
            return false
        }
        selected = []
        message = ""
        return true
    }

    // MARK: Liste complète et recherche

    // Lit tous les abonnements (ordre alphabétique), `maxFollowingPages` au plus.
    func loadAllFollowing() async {
        await load()
        var pages = 1
        while let cursor = following.nextCursor, pages < ShareRecipientRules.maxFollowingPages {
            await following.loadMore()
            pages += 1
            // Échec (curseur inchangé) : on s'arrête là.
            if following.nextCursor == cursor { break }
        }
        hasLoadedAllFollowing = true
    }

    // Amis = abonnés mutuels (les abonnements qui suivent en retour).
    private var friendIDs: Set<String> {
        Set(following.items.filter { $0.viewer?.followedBy == true }.map(\.user.id))
    }

    func isFriend(_ recipient: Recipient) -> Bool {
        if case .user(let user) = recipient.target { return friendIDs.contains(user.id) }
        return false
    }

    // « Chats récents », « Amis » (dans l'ordre des abonnements), puis tous les suivis de A à Z, rangés par lettre.
    var sections: [Section] {
        var result: [Section] = []
        if !recent.isEmpty { result.append(Section(kind: .recent, recipients: recent)) }
        let followed = following.items.map { Recipient(user: $0.user) }
        let friends = followed.filter(isFriend)
        if !friends.isEmpty { result.append(Section(kind: .friends, recipients: friends)) }
        let sorted = followed.sorted { ShareRecipientRules.precedes($0.title, $1.title) }
        var letters: [String] = []
        var byLetter: [String: [Recipient]] = [:]
        for recipient in sorted {
            let letter = ShareRecipientRules.section(for: recipient.title)
            if byLetter[letter] == nil { letters.append(letter) }
            byLetter[letter, default: []].append(recipient)
        }
        result += letters.map { Section(kind: .letter($0), recipients: byLetter[$0] ?? []) }
        return result
    }

    // Recherche : chats récents puis suivis dont le nom ou le pseudo contient le texte, sans doublon.
    var searchResults: [Recipient] {
        var seen = Set<String>()
        return (recent + following.items.map { Recipient(user: $0.user) }).filter { recipient in
            guard ShareRecipientRules.matches(query, title: recipient.title, username: recipient.username) else { return false }
            return seen.insert(recipient.id).inserted
        }
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Envoi direct (live)

    func send(to recipient: Recipient) async {
        guard deliveries[recipient.id] == nil else { return }
        deliveries[recipient.id] = .sending
        do {
            try await deliver(to: recipient, message: nil, clientMessageID: nil)
            deliveries[recipient.id] = .sent
        } catch {
            deliveries[recipient.id] = nil
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() } else { errorMessage = error.message }
        }
    }

    private func deliver(to recipient: Recipient, message: String?, clientMessageID: String?) async throws {
        switch (item, recipient.target) {
        case (.video(let video), .user(let user)):
            _ = try await share(videoID: video.id, to: user.username, message: message, clientMessageID: clientMessageID)
            interactions.sharedByMessage(video)
        case (.video(let video), .group(let conversationID)):
            _ = try await share(videoID: video.id, inConversation: conversationID, message: message, clientMessageID: clientMessageID)
            interactions.sharedByMessage(video)
        case (.live(let live), .user(let user)):
            guard let shareLive else { throw AppError.unexpected }
            _ = try await shareLive(liveID: live.id, to: user.username)
        case (.live(let live), .group(let conversationID)):
            guard let shareLive else { throw AppError.unexpected }
            _ = try await shareLive(liveID: live.id, inConversation: conversationID)
        }
    }
}
