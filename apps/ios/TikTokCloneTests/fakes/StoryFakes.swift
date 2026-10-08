import Foundation
import Synchronization

@testable import TikTokClone

// API des stories en mémoire (ADR-051) : lecture (rangée, stories d'un compte, vues, likes) et publication (stories
// `story-1`, `story-2`… ; une photo est publiée dès la confirmation, une vidéo passe en `processing`).
final class FakeStoryRepository: StoryRepository, StoryPublishingRepository {
    struct State {
        var tray: [StoryTrayEntry] = []
        var stories: [String: [Story]] = [:]
        var views: [String] = []
        var likes: [(String, Bool)] = []
        var viewers: [String: StoryViewersPage] = [:]
        var error: AppError?
        var likeError: AppError?
        var calls: [String] = []
        var partSize = 4
        var created: [(id: String, contentType: MediaContentType)] = []
        var completed: [String: [UploadedPart]] = [:]
        var deleted: [String] = []
        var own: [String: OwnVideo] = [:]
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    var views: [String] { state.withLock { $0.views } }
    var likes: [(String, Bool)] { state.withLock { $0.likes } }
    var deleted: [String] { state.withLock { $0.deleted } }
    var created: [(id: String, contentType: MediaContentType)] { state.withLock { $0.created } }

    func tray() async throws -> [StoryTrayEntry] {
        try state.withLock { state in
            state.calls.append("tray")
            if let error = state.error { throw error }
            return state.tray
        }
    }

    func stories(username: String) async throws -> [Story] {
        try state.withLock { state in
            state.calls.append("stories:\(username)")
            if let error = state.error { throw error }
            return state.stories[username] ?? []
        }
    }

    func recordView(storyID: String) async throws {
        state.withLock { $0.views.append(storyID) }
    }

    func setLiked(storyID: String, liked: Bool) async throws {
        try state.withLock { state in
            state.likes.append((storyID, liked))
            if let error = state.likeError { throw error }
        }
    }

    func viewers(storyID: String, cursor: String?) async throws -> StoryViewersPage {
        state.withLock { $0.viewers[storyID] ?? StoryViewersPage(viewers: [], nextCursor: nil, stats: StoryStats(viewers: 0, likes: 0)) }
    }

    func createUpload(contentType: MediaContentType, fileSize: Int) async throws -> UploadTicket {
        try state.withLock { state in
            if let error = state.error { throw error }
            let id = "story-\(state.created.count + 1)"
            state.created.append((id, contentType))
            state.own[id] = OwnVideo(id: id, description: nil, status: .uploading, thumbnailURL: nil, createdAt: .now)
            let count = max(1, (fileSize + state.partSize - 1) / state.partSize)
            let parts = (1...count).map { UploadTicket.Part(number: $0, url: URL(string: "http://storage.test/\(id)/\($0)")!) }
            return UploadTicket(videoID: id, partSize: state.partSize, parts: parts, expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        }
    }

    func completeUpload(storyID: String, parts: [UploadedPart]) async throws -> OwnVideo {
        state.withLock { state in
            state.completed[storyID] = parts
            let photo = state.created.first { $0.id == storyID }?.contentType == .jpeg
            let story = OwnVideo(
                id: storyID, description: nil, status: photo ? .ready : .processing,
                thumbnailURL: photo ? URL(string: "http://cdn.test/\(storyID)/photo.jpg") : nil, createdAt: .now)
            state.own[storyID] = story
            return story
        }
    }

    func story(id: String) async throws -> OwnVideo {
        try state.withLock { state in
            guard let story = state.own[id] else { throw AppError.notFound }
            return story
        }
    }

    func deleteStory(id: String) async throws {
        state.withLock { state in
            state.deleted.append(id)
            state.own[id] = nil
            for (username, stories) in state.stories { state.stories[username] = stories.filter { $0.id != id } }
        }
    }
}

// Rendu de photo factice : écrit un fichier `.jpg` dans le stockage de test.
struct FakeStoryPhotoRenderer: StoryPhotoRenderer {
    let store: InMemoryUploadStore

    func render(_ imageData: Data) async throws -> URL {
        store.addPickedFile("\(UUID().uuidString).jpg", imageData)
    }
}

extension Story {
    static func sample(
        _ id: String, by author: UserSummary = .bob, mediaType: StoryMediaType = .photo, viewed: Bool = false, liked: Bool = false,
        stats: StoryStats? = nil
    ) -> Story {
        Story(
            id: id, author: author, mediaType: mediaType, mediaURL: URL(string: "http://cdn.test/\(id)/media")!,
            thumbnailURL: URL(string: "http://cdn.test/\(id)/thumbnail.jpg")!, publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_086_400), viewed: viewed, liked: liked, stats: stats)
    }
}
