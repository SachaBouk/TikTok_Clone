import Foundation
import TikTokAPI

// Relations entre comptes par l'API (module interactions) : relation, abonnés et abonnements, blocage.
struct RemoteRelationshipRepository: RelationshipRepository {
    static let pageSize = 20

    let client: Client

    func relationship(username: String) async throws -> Relationship {
        switch try await mappingErrors({ try await client.getRelationship(path: .init(username: username)) }) {
        case .ok(let ok):
            let dto = try ok.body.json
            return Relationship(following: dto.following, followedBy: dto.followedBy, blockedByMe: dto.blockedByMe)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func relationships(userIDs: [String]) async throws -> [String: Relationship] {
        switch try await mappingErrors({ try await client.getRelationships(query: .init(userIds: userIDs)) }) {
        case .ok(let ok):
            let items = try ok.body.json.items
            return Dictionary(items.map { ($0.userId, Relationship(following: $0.following, followedBy: $0.followedBy, blockedByMe: $0.blockedByMe)) }) { first, _ in first }
        case .unauthorized: throw AppError.sessionExpired
        case .badRequest, .undocumented: throw AppError.unexpected
        }
    }

    func follows(_ kind: FollowListKind, username: String, cursor: String?) async throws -> FollowPage {
        let dto: Components.Schemas.FollowPageResponse
        switch kind {
        case .followers:
            switch try await mappingErrors({
                try await client.listFollowers(path: .init(username: username), query: .init(cursor: cursor, limit: Self.pageSize))
            }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case .following:
            switch try await mappingErrors({
                try await client.listFollowing(path: .init(username: username), query: .init(cursor: cursor, limit: Self.pageSize))
            }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        }
        return FollowPage(entries: dto.items.map(FollowEntry.init), nextCursor: dto.nextCursor)
    }

    func setBlocked(_ blocked: Bool, username: String) async throws {
        if blocked {
            switch try await mappingErrors({ try await client.blockUser(path: .init(username: username)) }) {
            case .noContent: return
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .unauthorized: throw AppError.sessionExpired
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        }
        switch try await mappingErrors({ try await client.unblockUser(path: .init(username: username)) }) {
        case .noContent: return
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        // Compte supprimé entre-temps : plus rien à débloquer.
        case .notFound: return
        case .undocumented: throw AppError.unexpected
        }
    }

    func blockedUsers() async throws -> [UserSummary] {
        switch try await mappingErrors({ try await client.listBlockedUsers() }) {
        case .ok(let ok): return try ok.body.json.items.map(UserSummary.init)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension FollowEntry {
    init(_ dto: Components.Schemas.FollowItemResponse) {
        self.init(
            user: UserSummary(dto.user),
            followedAt: dto.followedAt,
            viewer: dto.viewer.map { FollowViewer(following: $0.following, followedBy: $0.followedBy) }
        )
    }
}

// Listes de vidéos au format du feed (module feed) : grilles du profil et historique de visionnage.
struct RemoteVideoListRepository: VideoListRepository {
    // 3 colonnes : 7 lignes par page.
    static let pageSize = 21

    let client: Client

    func page(of list: VideoList, cursor: String?) async throws -> FeedPage {
        let dto: Components.Schemas.VideoPageResponse
        switch list {
        case .accountVideos(let username):
            switch try await mappingErrors({
                try await client.listAccountVideos(path: .init(username: username), query: .init(cursor: cursor, limit: Self.pageSize))
            }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case .reposts(let username):
            switch try await mappingErrors({
                try await client.listReposts(path: .init(username: username), query: .init(cursor: cursor, limit: Self.pageSize))
            }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .notFound: throw AppError.notFound
            case .undocumented: throw AppError.unexpected
            }
        case .myFavorites:
            switch try await mappingErrors({ try await client.listMyFavorites(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        case .myLikes:
            switch try await mappingErrors({ try await client.listMyLikes(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        case .myHistory:
            switch try await mappingErrors({ try await client.listMyHistory(query: .init(cursor: cursor, limit: Self.pageSize)) }) {
            case .ok(let ok): dto = try ok.body.json
            case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
            case .unauthorized: throw AppError.sessionExpired
            case .undocumented: throw AppError.unexpected
            }
        }
        return FeedPage(videos: dto.items.compactMap(FeedVideo.init), nextCursor: dto.nextCursor)
    }

    func removeFromHistory(videoID: String) async throws {
        switch try await mappingErrors({ try await client.removeFromHistory(path: .init(videoId: videoID)) }) {
        case .noContent: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func clearHistory() async throws {
        switch try await mappingErrors({ try await client.clearHistory() }) {
        case .noContent: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}
