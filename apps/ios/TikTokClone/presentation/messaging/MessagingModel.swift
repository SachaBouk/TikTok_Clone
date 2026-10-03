import Foundation
import Observation

// Écran de conversation ouvert : reçoit les événements temps réel de sa conversation (MessagingModel).
@MainActor
protocol ConversationObserver: AnyObject {
    var conversationID: String? { get }
    func received(_ message: DirectMessage)
    func removed(messageID: String)
    func read(by readerID: String, upTo messageID: String)
    func updated(_ conversation: Conversation)
    // Supprimée pour le compte connecté, ou demande refusée, peut-être sur un autre appareil.
    func conversationDeleted()
    // Connexion temps réel rétablie : rien n'est rejoué, l'écran relit son état.
    func reconnected() async
}

// Messagerie du compte connecté, partagée par toute l'app (AppContainer) : badges (onglet « Boîte de réception »),
// conversations et demandes reçues, « en train d'écrire », suivis en direct (ADR-011).
// - Les badges sont relus à chaque (re)connexion du temps réel, puis pris dans chaque événement.
// - Un nouveau message fait remonter sa conversation en tête (ou l'ajoute, relue par l'API).
// - Les écrans de conversation ouverts reçoivent les événements de la leur (`ConversationObserver`).
// - Messages écrits sur cet appareil et pas encore acceptés par l'API (ADR-044), par conversation : « Envoi… » ou
//   « Non envoyé », gardés pendant la session de l'app (même conversation fermée), oubliés à l'écho de leur envoi.
@MainActor
@Observable
final class MessagingModel {
    private(set) var badges = MessagingBadges.zero
    // Boîte de réception : conversations acceptées et demandes envoyées.
    let inbox: PagedList<Conversation>
    // Demandes reçues en attente.
    let requests: PagedList<Conversation>
    // Conversations dont l'autre participant est en train d'écrire.
    private(set) var typingConversationIDs: Set<String> = []
    // Messages sortants par conversation, du plus ancien au plus récent.
    private(set) var outgoing: [String: [OutgoingMessage]] = [:]

    private let loadConversation: LoadConversationUseCase
    private let countUnread: CountUnreadMessagesUseCase
    private let answerRequest: AnswerMessageRequestUseCase
    private let deleteConversation: DeleteConversationUseCase
    private let sendTypingIndicator: SendTypingUseCase
    private let session: SessionStore
    private let typingDisplay: Duration
    private var typingTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [WeakConversationObserver] = []

    init(
        loadConversations: LoadConversationsUseCase,
        loadRequests: LoadMessageRequestsUseCase,
        loadConversation: LoadConversationUseCase,
        countUnread: CountUnreadMessagesUseCase,
        answerRequest: AnswerMessageRequestUseCase,
        deleteConversation: DeleteConversationUseCase,
        sendTyping: SendTypingUseCase,
        session: SessionStore,
        typingDisplay: Duration = MessageRules.typingDisplay
    ) {
        self.loadConversation = loadConversation
        self.countUnread = countUnread
        self.answerRequest = answerRequest
        self.deleteConversation = deleteConversation
        sendTypingIndicator = sendTyping
        self.session = session
        self.typingDisplay = typingDisplay
        inbox = PagedList(session: session) { cursor in
            let page = try await loadConversations(cursor: cursor)
            return (page.conversations, page.nextCursor)
        }
        requests = PagedList(session: session) { cursor in
            let page = try await loadRequests(cursor: cursor)
            return (page.conversations, page.nextCursor)
        }
    }

    // Part de la messagerie dans le badge de l'onglet (choix du développeur : demandes comprises).
    var badgeCount: Int { badges.unreadConversations + badges.pendingRequests }

    func isTyping(in conversationID: String) -> Bool {
        typingConversationIDs.contains(conversationID)
    }

    // MARK: - Écrans

    func observe(_ observer: any ConversationObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakConversationObserver(value: observer))
    }

    // (Re)connexion du temps réel, retour au premier plan : rien n'est rejoué, on relit badges, listes chargées
    // et conversations ouvertes.
    func refresh() async {
        guard session.isSignedIn else { return }
        if let badges = try? await countUnread() { self.badges = badges }
        if inbox.state != .idle { await inbox.loadFirst() }
        if requests.state != .idle { await requests.loadFirst() }
        for observer in liveObservers() { await observer.reconnected() }
    }

    // Déconnexion : rien ne doit rester d'un compte à l'autre.
    func reset() {
        badges = .zero
        inbox.reset()
        requests.reset()
        for task in typingTasks.values { task.cancel() }
        typingTasks = [:]
        typingConversationIDs = []
        outgoing = [:]
        observers = []
    }

    // « En train d'écrire » dans une conversation (throttlé par l'écran).
    func sendTyping(in conversationID: String) async {
        await sendTypingIndicator(conversationID: conversationID)
    }

    // MARK: - Messages sortants (ADR-044)

    func outgoing(in conversationID: String) -> [OutgoingMessage] {
        outgoing[conversationID] ?? []
    }

    // Nouveau message à envoyer : à la suite des autres.
    func addOutgoing(_ message: OutgoingMessage) {
        outgoing[message.conversationID, default: []].append(message)
    }

    // Nouvel état d'un message encore en attente (sans effet s'il est déjà parti : écho reçu, ou supprimé).
    func setOutgoing(_ id: String, in conversationID: String, state: OutgoingMessage.State) {
        guard let index = outgoing[conversationID]?.firstIndex(where: { $0.id == id }) else { return }
        outgoing[conversationID]?[index].state = state
    }

    // Accepté par l'API, ou supprimé par l'utilisateur.
    func removeOutgoing(_ id: String, in conversationID: String) {
        outgoing[conversationID]?.removeAll { $0.id == id }
        if outgoing[conversationID]?.isEmpty == true { outgoing[conversationID] = nil }
    }

    // MARK: - Actions des écrans

    // Message envoyé depuis cet appareil : la ligne remonte en tête (l'événement `messageCreated` suivra).
    func sent(_ message: DirectMessage, in conversation: Conversation) {
        requests.remove { $0.id == conversation.id }
        moveToTop(conversation, in: inbox)
    }

    // Conversation affichée et lue : badges de l'API, ligne sans pastille.
    func markedRead(_ conversationID: String, badges: MessagingBadges) {
        self.badges = badges
        updateRows(conversationID) { $0.unreadCount = 0 }
    }

    // Demande acceptée depuis son écran : elle passe dans la boîte de réception.
    func accepted(_ conversation: Conversation) {
        requests.remove { $0.id == conversation.id }
        moveToTop(conversation, in: inbox)
    }

    // Conversation supprimée, ou demande refusée, depuis cet appareil : ses messages non envoyés avec.
    func removed(_ conversationID: String) {
        inbox.remove { $0.id == conversationID }
        requests.remove { $0.id == conversationID }
        outgoing[conversationID] = nil
    }

    // Glisser dans la boîte de réception : supprimer pour soi. Renvoie un message d'erreur.
    func delete(_ conversation: Conversation) async -> String? {
        await perform {
            try await self.deleteConversation(conversation.id)
        } then: {
            self.removed(conversation.id)
        }
    }

    // Glisser dans les demandes : refuser.
    func decline(_ conversation: Conversation) async -> String? {
        await perform {
            try await self.answerRequest.decline(conversation.id)
        } then: {
            self.removed(conversation.id)
        }
    }

    // MARK: - Temps réel

    func handle(_ update: RealtimeUpdate) {
        switch update {
        case .messageCreated(let message, let badges):
            self.badges = badges
            messageCreated(message)
        case .messageDeleted(let conversationID, let messageID, let badges):
            self.badges = badges
            for observer in liveObservers(of: conversationID) { observer.removed(messageID: messageID) }
            if row(conversationID)?.lastMessage?.id == messageID { reloadRow(conversationID) }
        case .conversationRead(let conversationID, let readerID, let lastReadMessageID, let badges):
            self.badges = badges
            if readerID == session.profile?.id {
                // Lue sur un autre appareil.
                updateRows(conversationID) { $0.unreadCount = 0 }
            } else {
                updateRows(conversationID) { $0.participantLastReadMessageID = lastReadMessageID }
                for observer in liveObservers(of: conversationID) { observer.read(by: readerID, upTo: lastReadMessageID) }
            }
        case .conversationAccepted(let conversationID, let badges):
            self.badges = badges
            reloadRow(conversationID, notify: true)
        case .conversationDeleted(let conversationID, let badges):
            self.badges = badges
            removed(conversationID)
            for observer in liveObservers(of: conversationID) { observer.conversationDeleted() }
        case .typing(let conversationID, let userID):
            guard userID != session.profile?.id else { return }
            showTyping(in: conversationID)
        case .connected, .videoProcessed, .notificationCreated, .unreadNotificationsChanged, .notificationsRemoved, .profileCountersChanged,
            .walletUpdated:
            break
        }
    }

    private func messageCreated(_ message: DirectMessage) {
        let fromOther = message.senderID != session.profile?.id
        if fromOther { hideTyping(in: message.conversationID) }
        // Écho de son propre envoi (il précède parfois la réponse, ou la remplace si elle s'est perdue).
        if let clientMessageID = message.clientMessageID { removeOutgoing(clientMessageID, in: message.conversationID) }
        for observer in liveObservers(of: message.conversationID) { observer.received(message) }

        let list = [inbox, requests].first { list in list.items.contains { $0.id == message.conversationID } }
        guard let list, var conversation = list.items.first(where: { $0.id == message.conversationID }) else {
            // Nouvelle conversation, ou demande : relue par l'API pour la placer.
            reloadRow(message.conversationID)
            return
        }
        conversation.lastMessage = message
        conversation.unreadCount = fromOther ? conversation.unreadCount + 1 : 0
        moveToTop(conversation, in: list)
    }

    private func showTyping(in conversationID: String) {
        typingConversationIDs.insert(conversationID)
        typingTasks[conversationID]?.cancel()
        typingTasks[conversationID] = Task { [typingDisplay] in
            try? await Task.sleep(for: typingDisplay)
            guard !Task.isCancelled else { return }
            hideTyping(in: conversationID)
        }
    }

    private func hideTyping(in conversationID: String) {
        typingTasks.removeValue(forKey: conversationID)?.cancel()
        typingConversationIDs.remove(conversationID)
    }

    // MARK: - Lignes des listes

    private func row(_ conversationID: String) -> Conversation? {
        (inbox.items + requests.items).first { $0.id == conversationID }
    }

    private func updateRows(_ conversationID: String, _ change: (inout Conversation) -> Void) {
        for list in [inbox, requests] {
            guard var conversation = list.items.first(where: { $0.id == conversationID }) else { continue }
            change(&conversation)
            list.replace(conversation)
        }
    }

    private func moveToTop(_ conversation: Conversation, in list: PagedList<Conversation>) {
        guard list.state == .loaded else { return }
        list.remove { $0.id == conversation.id }
        list.prepend(conversation)
    }

    // Relit une conversation et la place dans la bonne liste (demande reçue ou boîte de réception) ;
    // la retire si elle n'a plus de message visible ou n'existe plus.
    private func reloadRow(_ conversationID: String, notify: Bool = false) {
        Task {
            do {
                let conversation = try await loadConversation(id: conversationID)
                if notify {
                    for observer in liveObservers(of: conversationID) { observer.updated(conversation) }
                }
                guard conversation.lastMessage != nil else {
                    removed(conversationID)
                    return
                }
                let target = conversation.status == .requestReceived ? requests : inbox
                let other = target === inbox ? requests : inbox
                other.remove { $0.id == conversationID }
                if target.items.contains(where: { $0.id == conversationID }) {
                    target.replace(conversation)
                } else {
                    moveToTop(conversation, in: target)
                }
            } catch AppError.notFound {
                removed(conversationID)
            } catch AppError.sessionExpired {
                session.sessionExpired()
            } catch {
                // Réseau : la prochaine reconnexion relira les listes.
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void, then success: () -> Void) async -> String? {
        do {
            try await action()
            success()
            return nil
        } catch AppError.sessionExpired {
            session.sessionExpired()
            return nil
        } catch {
            return AppError.from(error).message
        }
    }

    private func liveObservers(of conversationID: String? = nil) -> [any ConversationObserver] {
        observers.removeAll { $0.value == nil }
        return observers.compactMap(\.value).filter { conversationID == nil || $0.conversationID == conversationID }
    }
}

private struct WeakConversationObserver {
    weak var value: (any ConversationObserver)?
}
