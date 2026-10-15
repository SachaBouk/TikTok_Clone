// Cas d'usage de la messagerie directe (ADR-002).

struct LoadConversationsUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(cursor: String?) async throws -> ConversationPage {
        try await messaging.conversations(cursor: cursor)
    }
}

struct LoadMessageRequestsUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(cursor: String?) async throws -> ConversationPage {
        try await messaging.requests(cursor: cursor)
    }
}

// Conversation par son identifiant (événement temps réel, rechargement), ou avec un compte (bouton « Message »).
struct LoadConversationUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(id: String) async throws -> Conversation {
        try await messaging.conversation(id: id)
    }

    func callAsFunction(username: String) async throws -> Conversation {
        try await messaging.open(username: username)
    }
}

struct CountUnreadMessagesUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction() async throws -> MessagingBadges {
        try await messaging.badges()
    }
}

struct LoadMessagesUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(conversationID: String, cursor: String?) async throws -> MessagePage {
        try await messaging.messages(conversationID: conversationID, cursor: cursor)
    }
}

// Texte nettoyé comme l'API (1 000 caractères au plus), vidéo partagée, ou les deux.
struct SendMessageUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(conversationID: String, text: String, videoID: String? = nil, clientMessageID: String? = nil) async throws -> DirectMessage {
        let content = MessageRules.cleaned(text)
        if let content, content.count > MessageRules.maxLength {
            throw AppError.rejected("Un message compte \(MessageRules.maxLength) caractères au plus.")
        }
        guard content != nil || videoID != nil else { throw AppError.rejected("Le message est vide.") }
        return try await messaging.send(conversationID: conversationID, content: content, videoID: videoID, clientMessageID: clientMessageID)
    }
}

// Partage d'une vidéo avec un compte (feuille « Envoyer par message ») : sa conversation, ouverte au besoin.
struct ShareVideoByMessageUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(videoID: String, to username: String) async throws -> DirectMessage {
        let conversation = try await messaging.open(username: username)
        return try await messaging.send(conversationID: conversation.id, content: nil, videoID: videoID, clientMessageID: nil)
    }

    // Dans une conversation déjà ouverte (un groupe, ADR-059).
    func callAsFunction(videoID: String, inConversation conversationID: String) async throws -> DirectMessage {
        try await messaging.send(conversationID: conversationID, content: nil, videoID: videoID, clientMessageID: nil)
    }
}

struct MarkConversationReadUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(conversationID: String, upToID: String) async throws -> MessagingBadges {
        try await messaging.markRead(conversationID: conversationID, upToID: upToID)
    }
}

// Demande reçue : accepter (renvoie la conversation devenue libre) ou refuser (elle disparaît, l'expéditeur
// n'est pas prévenu).
struct AnswerMessageRequestUseCase: Sendable {
    let messaging: any MessagingRepository

    func accept(_ conversationID: String) async throws -> Conversation {
        try await messaging.accept(conversationID: conversationID)
    }

    func decline(_ conversationID: String) async throws {
        try await messaging.decline(conversationID: conversationID)
    }
}

struct DeleteConversationUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(_ conversationID: String) async throws {
        try await messaging.deleteConversation(id: conversationID)
    }
}

struct DeleteMessageUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(_ messageID: String) async throws {
        try await messaging.deleteMessage(id: messageID)
    }
}

// « En train d'écrire », envoyé sur la connexion temps réel ; perdu sans connexion (rien n'est stocké).
struct SendTypingUseCase: Sendable {
    let channel: any RealtimeChannel

    func callAsFunction(conversationID: String) async {
        await channel.sendTyping(conversationID: conversationID)
    }
}

// Chats de groupe (ADR-059) : création (au moins 2 amis, 31 au plus), nom nettoyé comme l'API (50 caractères).
struct CreateGroupUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(userIDs: [String], name: String) async throws -> Conversation {
        guard GroupRules.canCreate(selected: userIDs.count) else {
            throw AppError.rejected("Choisis au moins \(GroupRules.minFriends) amis (\(GroupRules.maxMembers - 1) au plus).")
        }
        let name = GroupRules.cleanedName(name)
        if let name, name.count > GroupRules.maxNameLength {
            throw AppError.rejected("Le nom du groupe compte \(GroupRules.maxNameLength) caractères au plus.")
        }
        return try await messaging.createGroup(userIDs: userIDs, name: name)
    }
}

// Réglages d'un groupe : nom, membres, départ, sourdine.
struct ManageGroupUseCase: Sendable {
    let messaging: any MessagingRepository

    func rename(_ conversationID: String, to name: String) async throws -> Conversation {
        let name = GroupRules.cleanedName(name)
        if let name, name.count > GroupRules.maxNameLength {
            throw AppError.rejected("Le nom du groupe compte \(GroupRules.maxNameLength) caractères au plus.")
        }
        return try await messaging.renameGroup(conversationID: conversationID, name: name)
    }

    func add(_ userIDs: [String], to conversationID: String) async throws -> Conversation {
        try await messaging.addGroupMembers(conversationID: conversationID, userIDs: userIDs)
    }

    func remove(_ userID: String, from conversationID: String) async throws {
        try await messaging.removeGroupMember(conversationID: conversationID, userID: userID)
    }

    func leave(_ conversationID: String) async throws {
        try await messaging.leaveGroup(conversationID: conversationID)
    }

    func setMuted(_ muted: Bool, _ conversationID: String) async throws {
        try await messaging.setGroupMuted(conversationID: conversationID, muted: muted)
    }
}

// Amis (abonnés mutuels) qu'on peut ajouter à un groupe : ses abonnements qui le suivent en retour, page par page ;
// avec un texte, la recherche de comptes (ADR-049) restreinte aux amis.
struct LoadFriendsUseCase: Sendable {
    let relationships: any RelationshipRepository
    let search: any SearchRepository

    func callAsFunction(username: String, cursor: String?) async throws -> (friends: [UserSummary], nextCursor: String?) {
        let page = try await relationships.follows(.following, username: username, cursor: cursor)
        return (page.entries.filter { $0.viewer?.followedBy == true }.map(\.user), page.nextCursor)
    }

    func search(_ query: String) async throws -> [UserSummary] {
        let page = try await search.searchAccounts(query: query, cursor: nil)
        return page.results.filter { $0.viewer?.following == true && $0.viewer?.followedBy == true }.map(\.user)
    }
}
