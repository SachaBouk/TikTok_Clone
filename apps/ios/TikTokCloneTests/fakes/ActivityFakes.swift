import Foundation
import Synchronization

@testable import TikTokClone

// Centre d'activité en mémoire : notifications du plus récent au plus ancien, 2 par page, regroupées comme
// l'API ; « marquer lu » passe en lues la notification indiquée et les plus anciennes.
final class FakeActivityRepository: ActivityRepository {
    struct State {
        var notifications: [ActivityNotification] = []
        var markedUpTo: [String?] = []
        var filters: [ActivityFilter?] = []
        var error: AppError?
    }

    let state = Mutex(State())

    var markedUpTo: [String?] { state.withLock { $0.markedUpTo } }
    var filters: [ActivityFilter?] { state.withLock { $0.filters } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func add(_ notification: ActivityNotification) {
        state.withLock { $0.notifications.insert(notification, at: 0) }
    }

    func groups(kinds: [ActivityKind], cursor: String?) async throws -> ActivityGroupPage {
        try state.withLock { state in
            if let error = state.error { throw error }
            var groups: [ActivityGroup] = []
            for notification in state.notifications.reversed() where kinds.isEmpty || kinds.contains(notification.kind) {
                let key = ActivityGroup.key(for: notification)
                let existing = groups.first { $0.key == key }
                groups.removeAll { $0.key == key }
                groups.insert(ActivityGroup.merging(notification, into: existing), at: 0)
            }
            let start = cursor.flatMap { c in groups.firstIndex { $0.latestID == c }.map { $0 + 1 } } ?? 0
            let page = Array(groups.dropFirst(start).prefix(2))
            let next = start + 2 < groups.count ? page.last?.latestID : nil
            return ActivityGroupPage(groups: page, nextCursor: next)
        }
    }

    func notifications(filter: ActivityFilter?, cursor: String?) async throws -> ActivityPage {
        try state.withLock { state in
            state.filters.append(filter)
            if let error = state.error { throw error }
            let all = state.notifications.filter { notification in
                guard let filter else { return true }
                return notification.kind == filter.kind && (filter.videoID == nil || notification.video?.id == filter.videoID)
            }
            let start = cursor.flatMap { c in all.firstIndex { $0.id == c }.map { $0 + 1 } } ?? 0
            let page = Array(all.dropFirst(start).prefix(2))
            let next = start + 2 < all.count ? page.last?.id : nil
            return ActivityPage(notifications: page, nextCursor: next)
        }
    }

    func unreadCount() async throws -> Int {
        try state.withLock { state in
            if let error = state.error { throw error }
            return state.notifications.count { !$0.read }
        }
    }

    func markRead(upToID: String?) async throws -> Int {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.markedUpTo.append(upToID)
            let index = upToID.flatMap { id in state.notifications.firstIndex { $0.id == id } } ?? 0
            state.notifications = state.notifications.enumerated().map { offset, notification in
                offset >= index ? notification.marked(read: true) : notification
            }
            return state.notifications.count { !$0.read }
        }
    }
}

extension ActivityNotification {
    static func sample(
        _ id: String,
        kind: ActivityKind = .like,
        read: Bool = false,
        actor: UserSummary = .bob,
        videoID: String = "v1"
    ) -> ActivityNotification {
        ActivityNotification(
            id: id,
            kind: kind,
            actor: actor,
            video: kind == .follow ? nil : Video(id: videoID, thumbnailURL: URL(string: "http://cdn.test/\(videoID)/thumbnail.jpg")),
            comment: kind == .comment ? Comment(id: "c1", content: "Super") : nil,
            read: read,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func marked(read: Bool) -> ActivityNotification {
        ActivityNotification(
            id: id, kind: kind, actor: actor, video: video, comment: comment, read: read, createdAt: createdAt, moderation: moderation)
    }
}
