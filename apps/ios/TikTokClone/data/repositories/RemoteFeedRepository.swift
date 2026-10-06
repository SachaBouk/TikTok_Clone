import Foundation
import TikTokAPI

struct RemoteFeedRepository: FeedRepository {
    static let pageSize = 10

    let client: Client

    func page(cursor: String?) async throws -> FeedPage {
        let output = try await mappingErrors { try await client.getFeed(query: .init(cursor: cursor, limit: Self.pageSize)) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return FeedPage(videos: page.items.compactMap(FeedVideo.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func followingPage(cursor: String?) async throws -> FeedPage {
        let output = try await mappingErrors { try await client.getFollowingFeed(query: .init(cursor: cursor, limit: Self.pageSize)) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return FeedPage(videos: page.items.compactMap(FeedVideo.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func video(id: String) async throws -> FeedVideo {
        switch try await mappingErrors({ try await client.getFeedItem(path: .init(id: id)) }) {
        case .ok(let ok):
            guard let video = FeedVideo(try ok.body.json) else { throw AppError.unexpected }
            return video
        case .badRequest, .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }
}

struct RemoteViewHistoryRepository: ViewHistoryRepository {
    let client: Client

    func recordView(videoID: String) async throws {
        let output = try await mappingErrors { try await client.recordView(path: .init(id: videoID)) }
        switch output {
        case .noContent: return
        case .unauthorized: throw AppError.sessionExpired
        // Vidéo supprimée depuis : rien à compter.
        case .notFound: return
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension UserSummary {
    init(_ dto: Components.Schemas.UserSummaryResponse) {
        self.init(id: dto.id, username: dto.username, displayName: dto.displayName, avatarURL: dto.avatarUrl.flatMap(URL.init(string:)))
    }
}

extension FeedVideo {
    // Mapping explicite du DTO (ADR-002). Nil si les URLs sont invalides : la vidéo est sautée.
    init?(_ dto: Components.Schemas.FeedItemResponse) {
        guard let hlsURL = URL(string: dto.hlsUrl), let thumbnailURL = URL(string: dto.thumbnailUrl) else { return nil }
        self.init(
            id: dto.id,
            description: dto.description,
            hlsURL: hlsURL,
            thumbnailURL: thumbnailURL,
            createdAt: dto.createdAt,
            stats: VideoStats(
                views: dto.viewsCount,
                likes: dto.likesCount,
                comments: dto.commentsCount,
                favorites: dto.favoritesCount,
                shares: dto.sharesCount,
                reposts: dto.repostsCount
            ),
            author: UserSummary(dto.author),
            viewer: dto.viewer.map {
                ViewerState(liked: $0.liked, favorited: $0.favorited, reposted: $0.reposted, followingAuthor: $0.followingAuthor)
            }
        )
    }
}
