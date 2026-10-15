import Foundation

// Cas d'usage du live (ADR-053).

struct StartLiveUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(title: String) async throws -> LiveConnection {
        if title.count > LiveRules.maxTitleLength { throw AppError.rejected("Le titre fait au plus \(LiveRules.maxTitleLength) caractères.") }
        return try await lives.start(title: LiveRules.sanitizedTitle(title))
    }
}

struct JoinLiveUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String) async throws -> LiveConnection {
        try await lives.join(liveID: liveID)
    }
}

struct LoadLiveUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String) async throws -> LiveStream {
        try await lives.live(id: liveID)
    }
}

struct EndLiveUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String) async throws -> LiveStream {
        try await lives.end(liveID: liveID)
    }
}

struct SendLiveMessageUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String, text: String) async throws -> LiveChatMessage {
        guard let content = LiveRules.sanitizedMessage(text) else {
            throw AppError.rejected("Un message fait de 1 à \(LiveRules.maxMessageLength) caractères.")
        }
        return try await lives.sendMessage(liveID: liveID, content: content)
    }
}

struct DeleteLiveMessageUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String, messageID: String) async throws {
        try await lives.deleteMessage(liveID: liveID, messageID: messageID)
    }
}

struct SendLiveHeartsUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(liveID: String, count: Int) async throws -> Int {
        try await lives.sendHearts(liveID: liveID, count: count)
    }
}

struct LoadFollowingLivesUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction() async throws -> [LiveStream] {
        try await lives.followingLives()
    }
}

struct LoadUserLiveUseCase: Sendable {
    let lives: any LiveRepository

    func callAsFunction(username: String) async throws -> LiveStream? {
        try await lives.userLive(username: username)
    }
}

// Partage d'un live en cours par message (ADR-053) : la conversation avec ce compte, puis le message.
struct ShareLiveByMessageUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(liveID: String, to username: String) async throws -> DirectMessage {
        let conversation = try await messaging.open(username: username)
        return try await messaging.shareLive(conversationID: conversation.id, liveID: liveID)
    }

    // Dans une conversation déjà ouverte (un groupe, ADR-059).
    func callAsFunction(liveID: String, inConversation conversationID: String) async throws -> DirectMessage {
        try await messaging.shareLive(conversationID: conversationID, liveID: liveID)
    }
}
