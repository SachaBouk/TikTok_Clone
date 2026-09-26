import Foundation
import TikTokAPI

// Centre d'activité par l'API (module notifications).
struct RemoteActivityRepository: ActivityRepository {
    static let pageSize = 20

    let client: Client

    func groups(cursor: String?) async throws -> ActivityGroupPage {
        let output = try await mappingErrors { try await client.listNotificationGroups(query: .init(cursor: cursor, limit: Self.pageSize)) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return ActivityGroupPage(groups: page.items.map(ActivityGroup.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func notifications(filter: ActivityFilter?, cursor: String?) async throws -> ActivityPage {
        let query = Operations.ListNotifications.Input.Query(
            cursor: cursor,
            limit: Self.pageSize,
            kind: filter.map { .init($0.kind) },
            videoId: filter?.videoID
        )
        let output = try await mappingErrors { try await client.listNotifications(query: query) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return ActivityPage(notifications: page.items.map(ActivityNotification.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func unreadCount() async throws -> Int {
        switch try await mappingErrors({ try await client.countUnreadNotifications() }) {
        case .ok(let ok): return try ok.body.json.unreadCount
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func markRead(upToID: String?) async throws -> Int {
        switch try await mappingErrors({ try await client.markNotificationsRead(body: .json(.init(upToId: upToID))) }) {
        case .ok(let ok): return try ok.body.json.unreadCount
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension ActivityNotification {
    // Mapping explicite (ADR-002) ; partagé avec l'événement temps réel `notificationCreated`.
    init(_ dto: Components.Schemas.NotificationResponse) {
        self.init(
            id: dto.id,
            kind: ActivityKind(dto.kind),
            actor: UserSummary(dto.actor),
            video: dto.video.map { Video(id: $0.id, thumbnailURL: URL(string: $0.thumbnailUrl)) },
            comment: dto.comment.map { Comment(id: $0.id, content: $0.content) },
            read: dto.read,
            createdAt: dto.createdAt
        )
    }
}

extension ActivityGroup {
    init(_ dto: Components.Schemas.NotificationGroupResponse) {
        self.init(
            key: dto.key,
            kind: ActivityKind(dto.kind),
            actors: dto.actors.map(UserSummary.init),
            count: dto.count,
            video: dto.video.map { ActivityNotification.Video(id: $0.id, thumbnailURL: URL(string: $0.thumbnailUrl)) },
            comment: dto.comment.map { ActivityNotification.Comment(id: $0.id, content: $0.content) },
            read: dto.read,
            latestID: dto.latestId,
            createdAt: dto.createdAt
        )
    }
}

extension Components.Schemas.NotificationType {
    init(_ kind: ActivityKind) {
        switch kind {
        case .like: self = .like
        case .comment: self = .comment
        case .follow: self = .follow
        case .repost: self = .repost
        }
    }
}

extension ActivityKind {
    init(_ dto: Components.Schemas.NotificationType) {
        switch dto {
        case .like: self = .like
        case .comment: self = .comment
        case .follow: self = .follow
        case .repost: self = .repost
        }
    }
}
