import Foundation
import Synchronization

@testable import TikTokClone

// Feed en mémoire : renvoie les pages prévues, dans l'ordre (feed principal et feed des abonnements confondus),
// et garde les curseurs demandés et le feed lu.
final class FakeFeedRepository: FeedRepository {
    private let state: Mutex<(pages: [Result<FeedPage, AppError>], cursors: [String?], feeds: [String])>

    init(_ pages: [Result<FeedPage, AppError>]) {
        state = Mutex((pages, [], []))
    }

    var requestedCursors: [String?] { state.withLock { $0.cursors } }
    // « feed » ou « following », dans l'ordre des requêtes.
    var requestedFeeds: [String] { state.withLock { $0.feeds } }
    // Vidéos seules disponibles (`video(id:)`).
    nonisolated(unsafe) var videos: [String: FeedVideo] = [:]

    func video(id: String) async throws -> FeedVideo {
        guard let video = videos[id] else { throw AppError.notFound }
        return video
    }

    func page(cursor: String?) async throws -> FeedPage {
        try next(cursor: cursor, feed: "feed")
    }

    func followingPage(cursor: String?) async throws -> FeedPage {
        try next(cursor: cursor, feed: "following")
    }

    func friendsPage(cursor: String?) async throws -> FeedPage {
        try next(cursor: cursor, feed: "friends")
    }

    private func next(cursor: String?, feed: String) throws -> FeedPage {
        try state.withLock { state in
            state.cursors.append(cursor)
            state.feeds.append(feed)
            guard !state.pages.isEmpty else { return FeedPage(videos: [], nextCursor: nil) }
            return try state.pages.removeFirst().get()
        }
    }
}

final class FakeViewHistoryRepository: ViewHistoryRepository {
    private let state = Mutex<(recorded: [String], error: AppError?)>(([], nil))

    var recorded: [String] { state.withLock { $0.recorded } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func recordView(videoID: String) async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.recorded.append(videoID)
        }
    }
}

// Lecteur simulé : enregistre les ordres reçus (ADR-002 : ViewModel testé sans AVFoundation).
@MainActor
final class FakePlayback: VideoPlayback {
    private(set) var loaded: [[String]] = []
    private(set) var played: [String] = []
    private(set) var pauseCount = 0
    // Position et durée renvoyées pour chaque vidéo (mesure du visionnage).
    var progress: [String: PlaybackProgress] = [:]

    func keepLoaded(_ videos: [FeedVideo]) { loaded.append(videos.map(\.id)) }
    func play(_ videoID: String) { played.append(videoID) }
    func pauseAll() { pauseCount += 1 }
    func progress(of videoID: String) -> PlaybackProgress? { progress[videoID] }
}

extension FeedVideo {
    static func sample(_ id: String, author: String = "bob", viewer: ViewerState? = nil) -> FeedVideo {
        FeedVideo(
            id: id,
            description: "Vidéo \(id)",
            hlsURL: URL(string: "http://cdn.test/\(id)/master.m3u8")!,
            thumbnailURL: URL(string: "http://cdn.test/\(id)/thumbnail.jpg")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            stats: VideoStats(views: 1, likes: 2, comments: 3, favorites: 4, shares: 5, reposts: 6),
            author: UserSummary(id: "\(author)-id", username: author, displayName: author.capitalized, avatarURL: nil),
            viewer: viewer
        )
    }
}

func page(_ ids: [String], next: String?) -> FeedPage {
    FeedPage(videos: ids.map { FeedVideo.sample($0) }, nextCursor: next)
}
