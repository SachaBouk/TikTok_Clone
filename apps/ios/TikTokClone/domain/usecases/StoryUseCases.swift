import Foundation

// Cas d'usage des stories (ADR-051).

struct LoadStoryTrayUseCase: Sendable {
    let stories: any StoryRepository

    func callAsFunction() async throws -> [StoryTrayEntry] {
        try await stories.tray()
    }
}

struct LoadUserStoriesUseCase: Sendable {
    let stories: any StoryRepository

    func callAsFunction(username: String) async throws -> [Story] {
        try await stories.stories(username: username)
    }
}

struct RecordStoryViewUseCase: Sendable {
    let stories: any StoryRepository

    func callAsFunction(storyID: String) async throws {
        try await stories.recordView(storyID: storyID)
    }
}

struct SetStoryLikedUseCase: Sendable {
    let stories: any StoryRepository

    func callAsFunction(storyID: String, liked: Bool) async throws {
        try await stories.setLiked(storyID: storyID, liked: liked)
    }
}

struct LoadStoryViewersUseCase: Sendable {
    let stories: any StoryRepository

    func callAsFunction(storyID: String, cursor: String?) async throws -> StoryViewersPage {
        try await stories.viewers(storyID: storyID, cursor: cursor)
    }
}

struct DeleteStoryUseCase: Sendable {
    let stories: any StoryPublishingRepository

    func callAsFunction(id: String) async throws {
        try await stories.deleteStory(id: id)
    }
}

// Réponse à une story : un message dans la conversation avec son auteur (existante ou nouvelle), avec la story en
// référence. Toutes les règles de la messagerie s'appliquent (demande, limites, blocage).
struct ReplyToStoryUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(_ story: Story, text: String, clientMessageID: String = UUID().uuidString) async throws -> DirectMessage {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AppError.rejected("Écris un message.") }
        guard content.count <= MessageRules.maxLength else {
            throw AppError.rejected("Un message fait au plus \(MessageRules.maxLength) caractères.")
        }
        let conversation = try await messaging.open(username: story.author.username)
        return try await messaging.replyToStory(
            conversationID: conversation.id, storyID: story.id, content: content, clientMessageID: clientMessageID)
    }
}

// Photo choisie pour une story : préparée (recadrée, réencodée sans métadonnées) avant l'envoi. Une photo qu'on ne sait
// pas préparer est refusée.
struct PrepareStoryPhotoUseCase: Sendable {
    let renderer: any StoryPhotoRenderer

    func callAsFunction(_ imageData: Data) async throws -> URL {
        do {
            return try await renderer.render(imageData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.rejected("Impossible de préparer cette photo.")
        }
    }
}
