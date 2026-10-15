import Foundation
import Synchronization

@testable import TikTokClone

// Relations en mémoire : relation par pseudo, listes d'abonnés, blocages.
final class FakeRelationshipRepository: RelationshipRepository {
    struct State {
        var relationships: [String: Relationship] = [:]
        // Relations par identifiant (`relationships(userIDs:)`).
        var relationshipsByID: [String: Relationship] = [:]
        var follows: [FollowListKind: [FollowEntry]] = [:]
        var blocked: [UserSummary] = []
        var calls: [String] = []
        var error: AppError?
    }

    let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func relationship(username: String) async throws -> Relationship {
        try state.withLock {
            $0.calls.append("relationship-\(username)")
            if let error = $0.error { throw error }
            return $0.relationships[username] ?? .empty
        }
    }

    func relationships(userIDs: [String]) async throws -> [String: Relationship] {
        try state.withLock { state in
            state.calls.append("relationships-\(userIDs.sorted().joined(separator: ","))")
            if let error = state.error { throw error }
            return Dictionary(uniqueKeysWithValues: userIDs.map { ($0, state.relationshipsByID[$0] ?? .empty) })
        }
    }

    func follows(_ kind: FollowListKind, username: String, cursor: String?) async throws -> FollowPage {
        try state.withLock {
            $0.calls.append("\(kind)-\(username)-\(cursor ?? "nil")")
            if let error = $0.error { throw error }
            return FollowPage(entries: $0.follows[kind] ?? [], nextCursor: nil)
        }
    }

    func setBlocked(_ blocked: Bool, username: String) async throws {
        try state.withLock {
            $0.calls.append("\(blocked ? "block" : "unblock")-\(username)")
            if let error = $0.error { throw error }
            if !blocked { $0.blocked.removeAll { $0.username == username } }
        }
    }

    func blockedUsers() async throws -> [UserSummary] {
        try state.withLock {
            if let error = $0.error { throw error }
            return $0.blocked
        }
    }
}

// Listes de vidéos en mémoire : une page par liste (curseur « next » si `nextCursors` en prévoit un).
final class FakeVideoListRepository: VideoListRepository {
    struct State {
        var pages: [VideoList: [FeedPage]] = [:]
        var requests: [String] = []
        var removed: [String] = []
        var cleared = 0
    }

    let state = Mutex(State())

    var requests: [String] { state.withLock { $0.requests } }
    func set(_ list: VideoList, _ pages: [FeedPage]) { state.withLock { $0.pages[list] = pages } }

    func page(of list: VideoList, cursor: String?) async throws -> FeedPage {
        state.withLock {
            $0.requests.append("\(list)-\(cursor ?? "nil")")
            let pages = $0.pages[list] ?? []
            let index = cursor.flatMap { Int($0) } ?? 0
            return pages.indices.contains(index) ? pages[index] : FeedPage(videos: [], nextCursor: nil)
        }
    }

    func removeFromHistory(videoID: String) async throws {
        state.withLock { $0.removed.append(videoID) }
    }

    func clearHistory() async throws {
        state.withLock { $0.cleared += 1 }
    }
}

final class FakeAvatarTransport: AvatarUploadTransport {
    let uploads = Mutex<[(size: Int, type: AvatarImageType, url: URL)]>([])

    var count: Int { uploads.withLock { $0.count } }

    func upload(_ data: Data, type: AvatarImageType, to url: URL) async throws {
        uploads.withLock { $0.append((data.count, type, url)) }
    }
}

extension UserProfile {
    static let bob = UserProfile(
        id: "bob-id", username: "bob", displayName: "Bob", avatarURL: nil, bio: "Salut",
        followersCount: 10, followingCount: 2, createdAt: Date(timeIntervalSince1970: 1_767_268_800)
    )
}

// Comptes suggérés (ADR-058) en mémoire.
final class FakeSuggestionRepository: SuggestionRepository {
    let stored: Mutex<[AccountSuggestion]>
    let calls = Mutex(0)

    init(_ suggestions: [AccountSuggestion] = []) {
        stored = Mutex(suggestions)
    }

    func suggestions() async throws -> [AccountSuggestion] {
        calls.withLock { $0 += 1 }
        return stored.withLock { $0 }
    }
}

// Suggestions écartées, en mémoire (ADR-058).
final class InMemoryDismissedSuggestionsStore: DismissedSuggestionsStore {
    private let stored: Mutex<[String]>

    init(_ ids: [String] = []) {
        stored = Mutex(ids)
    }

    var dismissedSuggestions: [String] { stored.withLock { $0 } }
    func setDismissedSuggestions(_ ids: [String]) { stored.withLock { $0 = ids } }
}
