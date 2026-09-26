// Cas d'usage du centre d'activité (ADR-002).

struct LoadActivityGroupsUseCase: Sendable {
    let activity: any ActivityRepository

    func callAsFunction(cursor: String?) async throws -> ActivityGroupPage {
        try await activity.groups(cursor: cursor)
    }
}

// Liste complète d'un groupe, une ligne par notification.
struct LoadActivityGroupUseCase: Sendable {
    let activity: any ActivityRepository

    func callAsFunction(_ filter: ActivityFilter, cursor: String?) async throws -> ActivityPage {
        try await activity.notifications(filter: filter, cursor: cursor)
    }
}

struct CountUnreadActivityUseCase: Sendable {
    let activity: any ActivityRepository

    func callAsFunction() async throws -> Int {
        try await activity.unreadCount()
    }
}

// À l'affichage du centre d'activité : la notification la plus récente affichée et les plus anciennes
// passent en lues ; celles arrivées depuis restent non lues. Renvoie le nouveau badge.
struct MarkActivityReadUseCase: Sendable {
    let activity: any ActivityRepository

    func callAsFunction(upToID: String) async throws -> Int {
        try await activity.markRead(upToID: upToID)
    }
}
