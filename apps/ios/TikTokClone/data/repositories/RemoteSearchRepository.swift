import Foundation
import TikTokAPI

// Recherche de comptes et hashtags (ADR-049) : routes publiques.
struct RemoteSearchRepository: SearchRepository {
    static let pageSize = 20

    let client: Client

    func searchAccounts(query: String, cursor: String?) async throws -> AccountSearchPage {
        switch try await mappingErrors({ try await client.searchUsers(query: .init(q: query, cursor: cursor, limit: Self.pageSize)) }) {
        case .ok(let ok):
            let page = try ok.body.json
            return AccountSearchPage(
                results: page.items.map { item in
                    AccountSearchResult(
                        user: UserSummary(item.user),
                        followersCount: item.followersCount,
                        viewer: item.viewer.map { FollowViewer(following: $0.following, followedBy: $0.followedBy) }
                    )
                },
                nextCursor: page.nextCursor
            )
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func searchHashtags(prefix: String, limit: Int) async throws -> [Hashtag] {
        switch try await mappingErrors({ try await client.searchHashtags(query: .init(q: prefix, limit: limit)) }) {
        case .ok(let ok): return try ok.body.json.items.map(Hashtag.init)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func trendingHashtags() async throws -> [Hashtag] {
        switch try await mappingErrors({ try await client.listTrendingHashtags() }) {
        case .ok(let ok): return try ok.body.json.items.map(Hashtag.init)
        case .undocumented: throw AppError.unexpected
        }
    }

    func hashtag(name: String) async throws -> Hashtag {
        switch try await mappingErrors({ try await client.getHashtag(path: .init(name: name)) }) {
        case .ok(let ok): return Hashtag(try ok.body.json)
        case .badRequest: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension Hashtag {
    // Mapping explicite du DTO (ADR-002).
    init(_ dto: Components.Schemas.HashtagResponse) {
        self.init(name: dto.name, videosCount: dto.videosCount)
    }
}
