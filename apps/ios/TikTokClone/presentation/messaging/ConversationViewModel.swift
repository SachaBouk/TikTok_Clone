import Foundation
import Observation

// Une conversation (fil de messages), ouverte depuis la boîte de réception, les demandes, ou le bouton
// « Message » d'un profil (conversation obtenue ou créée par pseudo).
// - Messages du plus ancien au plus récent ; les plus anciens se chargent en remontant.
// - Envoi : le message s'affiche aussitôt (« Envoi… »), puis prend sa place une fois accepté par l'API. En cas
//   d'échec, il reste affiché « Non envoyé », à réessayer ou supprimer (ADR-044) ; il est gardé par MessagingModel
//   pendant la session de l'app. Chaque essai porte le même identifiant d'envoi : un renvoi ne crée pas de doublon.
//   Une limite d'envoi (429) bloque l'envoi et le renvoi pendant le délai indiqué.
// - Tant que l'écran est affiché, ce qui y arrive est marqué lu (« Vu » chez l'autre, badges à jour).
// - « En train d'écrire » : envoyé au plus toutes les 3 s pendant la saisie, dans une conversation libre.
// - Groupe (ADR-059) : « Vu par … », « Inès écrit… », lignes d'événement ; réglages (nom, membres, sourdine, départ).
@MainActor
@Observable
final class ConversationViewModel: ConversationObserver {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    // Pseudo de l'autre participant quand la conversation est ouverte par lui (bouton « Message ») ; nil pour un groupe.
    let routeUsername: String?
    private let routeConversationID: String?
    private(set) var conversation: Conversation?
    // Du plus ancien au plus récent.
    private(set) var messages: [DirectMessage] = []
    private(set) var state: State = .loading
    private(set) var hasOlderMessages = false
    // Limite d'envoi atteinte : envoi impossible jusqu'à cette date.
    private(set) var sendBlockedUntil: Date?
    // Conversation supprimée ou demande refusée : l'écran se ferme.
    private(set) var isClosed = false
    var errorMessage: String?
    var draft = "" {
        didSet { draftChanged() }
    }

    private var nextCursor: String?
    private var isLoadingOlder = false
    private var isVisible = false
    // Un message de l'autre attend d'être marqué lu.
    private var needsMarkRead = false
    private var lastTypingSent: Date?

    private let loadConversation: LoadConversationUseCase
    private let loadMessages: LoadMessagesUseCase
    private let sendMessage: SendMessageUseCase
    private let markRead: MarkConversationReadUseCase
    private let answerRequest: AnswerMessageRequestUseCase
    private let deleteConversation: DeleteConversationUseCase
    private let deleteMessage: DeleteMessageUseCase
    private let manageGroup: ManageGroupUseCase?
    private let messaging: MessagingModel
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let now: () -> Date

    init(
        route: ConversationRoute,
        loadConversation: LoadConversationUseCase,
        loadMessages: LoadMessagesUseCase,
        sendMessage: SendMessageUseCase,
        markRead: MarkConversationReadUseCase,
        answerRequest: AnswerMessageRequestUseCase,
        deleteConversation: DeleteConversationUseCase,
        deleteMessage: DeleteMessageUseCase,
        manageGroup: ManageGroupUseCase? = nil,
        messaging: MessagingModel,
        session: SessionStore,
        analytics: AnalyticsModel,
        now: @escaping () -> Date = Date.init
    ) {
        routeUsername = route.username
        routeConversationID = route.conversationID
        conversation = route.conversation
        self.manageGroup = manageGroup
        self.loadConversation = loadConversation
        self.loadMessages = loadMessages
        self.sendMessage = sendMessage
        self.markRead = markRead
        self.answerRequest = answerRequest
        self.deleteConversation = deleteConversation
        self.deleteMessage = deleteMessage
        self.messaging = messaging
        self.session = session
        self.analytics = analytics
        self.now = now
    }

    var conversationID: String? { conversation?.id }
    // Messages écrits ici et pas encore acceptés : « Envoi… » ou « Non envoyé », après les messages.
    var pending: [OutgoingMessage] { conversationID.map(messaging.outgoing(in:)) ?? [] }
    var ownID: String? { session.profile?.id }
    var isOtherTyping: Bool { conversationID.map(messaging.isTyping(in:)) ?? false }

    // Pseudo de l'autre participant (conversation à deux).
    var username: String { conversation?.participant?.username ?? routeUsername ?? "" }

    var group: GroupChat? { conversation?.group }

    // Titre : le nom de l'autre participant ou du groupe (le pseudo tant que la conversation n'est pas chargée).
    var title: String {
        if let conversation { return conversation.title(ownID: ownID) }
        return routeUsername.map { "@\($0)" } ?? ""
    }

    // « Vu » (à deux) ou « Vu par Inès, Nathan » (groupe) sous son dernier message, s'il a été lu.
    var seen: (messageID: String, label: String)? {
        guard let ownID, let conversation else { return nil }
        if let group = conversation.group {
            guard let lastOwn = messages.last(where: { $0.senderID == ownID && $0.event == nil }),
                let label = GroupRules.seenLabel(group.seenBy(lastOwn, ownID: ownID))
            else { return nil }
            return (lastOwn.id, label)
        }
        return MessageRules.seenMessageID(in: messages, ownID: ownID, participantLastRead: conversation.participantLastReadMessageID).map {
            ($0, "Vu")
        }
    }

    // Groupe : « Inès écrit… », « 2 personnes écrivent… ».
    var typingLabel: String? {
        guard let conversationID, let group else { return nil }
        let names = messaging.typingUserIDs(in: conversationID).compactMap { id in group.members.first { $0.user.id == id }?.user.displayName }
        return GroupRules.typingLabel(names)
    }

    var isAdmin: Bool { group?.isAdmin(ownID) == true }

    var timestampedIDs: Set<String> { MessageRules.timestampedIDs(in: messages) }

    var isRequestReceived: Bool { conversation?.status == .requestReceived }

    // Le bouton d'envoi : conversation qui le permet, texte valide, pas de limite d'envoi en cours.
    func canSend(at date: Date) -> Bool {
        MessageRules.isValid(draft) && canRetry(at: date)
    }

    // « Réessayer » sur un message non envoyé : conversation qui le permet, pas de limite d'envoi en cours.
    func canRetry(at date: Date) -> Bool {
        guard conversation?.canSend == true else { return false }
        return sendBlockedUntil.map { date >= $0 } ?? true
    }

    // Secondes restantes avant de pouvoir envoyer à nouveau (limite d'envoi), nil sinon.
    func secondsBeforeSending(at date: Date) -> Int? {
        guard let sendBlockedUntil, date < sendBlockedUntil else { return nil }
        return Int(sendBlockedUntil.timeIntervalSince(date).rounded(.up))
    }

    // MARK: - Chargement

    func load() async {
        // Groupe quitté, conversation supprimée : plus rien à relire (l'écran se ferme).
        guard !isClosed else { return }
        if messages.isEmpty { state = .loading }
        do {
            let conversation = try await currentConversation()
            self.conversation = conversation
            messaging.observe(self)
            let page = try await loadMessages(conversationID: conversation.id, cursor: nil)
            // Toute la conversation tient dans la page : elle remplace ce qui était affiché.
            messages = page.nextCursor == nil ? page.messages.reversed() : merged(page.messages.reversed(), replacingFrom: page.messages.last?.id)
            nextCursor = page.nextCursor
            hasOlderMessages = page.nextCursor != nil
            needsMarkRead = conversation.unreadCount > 0
            state = .loaded
            markReadIfNeeded()
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            guard !isClosed else { return }
            let message = AppError.from(error).message
            if messages.isEmpty { state = .failed(message) } else { errorMessage = message }
        }
    }

    // Le premier message affiché apparaît : charge les plus anciens. Renvoie l'identifiant du message qui était
    // en tête, pour garder la position de lecture.
    func loadOlder() async -> String? {
        guard !isLoadingOlder, let cursor = nextCursor, let conversationID else { return nil }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let anchor = messages.first?.id
        do {
            let page = try await loadMessages(conversationID: conversationID, cursor: cursor)
            let known = Set(messages.map(\.id))
            messages = page.messages.reversed().filter { !known.contains($0.id) } + messages
            nextCursor = page.nextCursor
            hasOlderMessages = page.nextCursor != nil
            return anchor
        } catch AppError.sessionExpired {
            session.sessionExpired()
            return nil
        } catch {
            return nil
        }
    }

    // Écran réellement affiché (écran au premier plan, onglet sélectionné, app active).
    func setVisible(_ visible: Bool) {
        isVisible = visible
        markReadIfNeeded()
    }

    // MARK: - Envoi

    func send() async {
        guard let conversation, canSend(at: now()), let text = MessageRules.cleaned(draft) else { return }
        let outgoing = OutgoingMessage(conversationID: conversation.id, content: text)
        messaging.addOutgoing(outgoing)
        draft = ""
        lastTypingSent = nil
        await deliver(outgoing)
    }

    // Nouvel essai d'un message non envoyé, avec le même identifiant d'envoi.
    func retry(_ outgoing: OutgoingMessage) async {
        guard outgoing.state == .failed else { return }
        if let seconds = secondsBeforeSending(at: now()) {
            errorMessage = AppError.rateLimited(retryAfter: seconds).message
            return
        }
        guard canRetry(at: now()) else { return }
        messaging.setOutgoing(outgoing.id, in: outgoing.conversationID, state: .sending)
        await deliver(outgoing)
    }

    // Supprimer un message non envoyé : il n'est jamais parti (sinon son écho l'aurait déjà retiré).
    func discard(_ outgoing: OutgoingMessage) {
        messaging.removeOutgoing(outgoing.id, in: outgoing.conversationID)
    }

    // Retrait d'un de ses messages, pour les deux participants.
    func retract(_ message: DirectMessage) async {
        do {
            try await deleteMessage(message.id)
            messages.removeAll { $0.id == message.id }
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
    }

    // MARK: - Demandes et suppression

    func accept() async {
        guard let conversationID else { return }
        do {
            let conversation = try await answerRequest.accept(conversationID)
            self.conversation = conversation
            messaging.accepted(conversation)
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
    }

    // Refuser : la demande disparaît (l'expéditeur n'en sait rien) et l'écran se ferme.
    func decline() async {
        await close { try await self.answerRequest.decline($0) }
    }

    // Supprimer pour soi : l'autre garde tout ; l'écran se ferme.
    func delete() async {
        await close { try await self.deleteConversation($0) }
    }

    // MARK: - Groupe (ADR-059)

    // Renommer (vide : nom retiré) ; renvoie vrai si c'est fait.
    @discardableResult
    func rename(to name: String) async -> Bool {
        await updateGroup { try await $0.rename($1, to: name) }
    }

    func addMembers(_ users: [UserSummary]) async -> Bool {
        await updateGroup { try await $0.add(users.map(\.id), to: $1) }
    }

    // L'administrateur retire un membre ; il disparaît aussitôt de la liste (la ligne d'événement suivra).
    func removeMember(_ user: UserSummary) async {
        guard let manageGroup, let conversationID else { return }
        do {
            try await manageGroup.remove(user.id, from: conversationID)
            conversation?.group?.members.removeAll { $0.user.id == user.id }
            if let conversation { messaging.groupChanged(conversation) }
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
    }

    // Sourdine : affichée tout de suite, rétablie en cas d'échec.
    func setMuted(_ muted: Bool) async {
        guard let manageGroup, let conversationID, group != nil else { return }
        conversation?.group?.muted = muted
        do {
            try await manageGroup.setMuted(muted, conversationID)
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            conversation?.group?.muted = !muted
            errorMessage = AppError.from(error).message
        }
    }

    // Quitter le groupe : l'écran se ferme.
    func leave() async {
        guard let manageGroup else { return }
        await close { try await manageGroup.leave($0) }
    }

    private func updateGroup(_ action: (ManageGroupUseCase, String) async throws -> Conversation) async -> Bool {
        guard let manageGroup, let conversationID else { return false }
        do {
            let updated = try await action(manageGroup, conversationID)
            conversation = updated
            messaging.groupChanged(updated)
            return true
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
        return false
    }

    // MARK: - ConversationObserver

    func received(_ message: DirectMessage) {
        guard message.conversationID == conversationID else { return }
        // Son propre envoi (ici ou sur un autre appareil) : MessagingModel a retiré sa bulle en attente.
        if message.senderID != ownID { needsMarkRead = true }
        insert(message)
        conversation?.lastMessage = messages.last
        markReadIfNeeded()
    }

    func removed(messageID: String) {
        messages.removeAll { $0.id == messageID }
    }

    func read(by readerID: String, upTo messageID: String) {
        guard readerID != ownID, var conversation else { return }
        conversation.read(by: readerID, upTo: messageID)
        self.conversation = conversation
    }

    func updated(_ conversation: Conversation) {
        guard conversation.id == conversationID else { return }
        self.conversation = conversation
    }

    func conversationDeleted() {
        isClosed = true
    }

    func reconnected() async {
        guard state == .loaded else { return }
        await load()
    }

    // MARK: - Privé

    private func currentConversation() async throws -> Conversation {
        if let id = conversation?.id ?? routeConversationID { return try await loadConversation(id: id) }
        return try await loadConversation(username: routeUsername ?? "")
    }

    // Page la plus récente (du plus ancien au plus récent) fusionnée avec les messages déjà affichés : les plus
    // anciens sont gardés, ceux de la période couverte par la page sont remplacés (un message retiré disparaît).
    private func merged(_ page: [DirectMessage], replacingFrom oldestID: String?) -> [DirectMessage] {
        guard let oldestID else { return page }
        return messages.filter { !MessageRules.isAtOrBefore(oldestID, $0.id) } + page
    }

    private func insert(_ message: DirectMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        if messages.count > 1, !MessageRules.isAtOrBefore(messages[messages.count - 2].id, message.id) {
            messages.sort { MessageRules.isAtOrBefore($0.id, $1.id) }
        }
    }

    private func markReadIfNeeded() {
        guard isVisible, needsMarkRead, let conversationID, let newest = messages.last?.id else { return }
        needsMarkRead = false
        Task {
            do {
                let badges = try await markRead(conversationID: conversationID, upToID: newest)
                messaging.markedRead(conversationID, badges: badges)
                conversation?.unreadCount = 0
            } catch AppError.sessionExpired {
                session.sessionExpired()
            } catch {
                // Réessayé au prochain message reçu ou au prochain affichage.
                needsMarkRead = true
            }
        }
    }

    private func draftChanged() {
        guard let conversation, conversation.allowsTyping, MessageRules.cleaned(draft) != nil else { return }
        let date = now()
        if let lastTypingSent, date.timeIntervalSince(lastTypingSent) < MessageRules.typingInterval.seconds { return }
        lastTypingSent = date
        Task { await messaging.sendTyping(in: conversation.id) }
    }

    private func deliver(_ outgoing: OutgoingMessage) async {
        do {
            let message = try await sendMessage(conversationID: outgoing.conversationID, text: outgoing.content, clientMessageID: outgoing.id)
            messaging.removeOutgoing(outgoing.id, in: outgoing.conversationID)
            insert(message)
            guard let conversation else { return }
            analytics.track(.messageSent(conversationID: conversation.id, status: conversation.status))
            let updated = conversation.afterSending(message)
            self.conversation = updated
            messaging.sent(message, in: updated)
        } catch {
            messaging.setOutgoing(outgoing.id, in: outgoing.conversationID, state: .failed)
            await handleSendError(error)
        }
    }

    private func handleSendError(_ error: any Error) async {
        switch AppError.from(error) {
        case .sessionExpired:
            session.sessionExpired()
        case .network:
            // Coupure : la bulle « Non envoyé » suffit, à réessayer une fois la connexion revenue.
            break
        case .rateLimited(let seconds):
            sendBlockedUntil = now().addingTimeInterval(TimeInterval(seconds))
        case .rejected(let message):
            // Blocage ou demande épuisée : la conversation relue dit ce qui est encore possible.
            errorMessage = message
            if let id = conversationID, let conversation = try? await loadConversation(id: id) { self.conversation = conversation }
        case let other:
            errorMessage = other.message
        }
    }

    private func close(_ action: (String) async throws -> Void) async {
        guard let conversationID else { return }
        do {
            try await action(conversationID)
            messaging.removed(conversationID)
            isClosed = true
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AppError.from(error).message
        }
    }
}

// Conversation à ouvrir : par son pseudo (bouton « Message »), par son identifiant (message de groupe trouvé, ADR-059),
// ou déjà chargée (listes).
struct ConversationRoute: Hashable {
    let username: String?
    let conversationID: String?
    let conversation: Conversation?

    init(username: String) {
        self.username = username
        conversationID = nil
        conversation = nil
    }

    init(id: String) {
        username = nil
        conversationID = id
        conversation = nil
    }

    init(_ conversation: Conversation) {
        username = conversation.participant?.username
        conversationID = conversation.id
        self.conversation = conversation
    }

    // Une conversation à deux s'identifie par l'autre participant, un groupe par son identifiant.
    private var key: String { username.map { "@\($0)" } ?? conversationID ?? "" }

    static func == (lhs: ConversationRoute, rhs: ConversationRoute) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
