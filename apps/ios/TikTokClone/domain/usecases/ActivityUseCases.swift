// Cas d'usage du centre d'activité (ADR-002).

// « Suivre en retour » : relation avec les auteurs d'abonnements affichés un par un, en une requête par page.
// Les notifications ne la portent pas : elle appartient au module interactions, qui dépend de notifications
// (ADR-003, ADR-036). Échec : pas de bouton, la page s'affiche quand même.
struct LoadActorRelationshipsUseCase: Sendable {
    let relationships: any RelationshipRepository

    func callAsFunction(_ userIDs: [String]) async -> [String: Relationship] {
        let ids = Array(Set(userIDs))
        guard !ids.isEmpty else { return [:] }
        return (try? await relationships.relationships(userIDs: ids)) ?? [:]
    }
}

struct LoadActivityGroupsUseCase: Sendable {
    let activity: any ActivityRepository
    let actorRelationships: LoadActorRelationshipsUseCase

    func callAsFunction(cursor: String?) async throws -> ActivityGroupPage {
        let page = try await activity.groups(cursor: cursor)
        let relationships = await actorRelationships(page.groups.compactMap(\.followBackActor?.id))
        let groups = page.groups.map { group in
            var group = group
            if let actor = group.followBackActor { group.actorRelationship = relationships[actor.id] }
            return group
        }
        return ActivityGroupPage(groups: groups, nextCursor: page.nextCursor)
    }
}

// Liste complète d'un groupe, une ligne par notification ; les abonnements avec leur relation.
struct LoadActivityGroupUseCase: Sendable {
    let activity: any ActivityRepository
    let actorRelationships: LoadActorRelationshipsUseCase

    func callAsFunction(_ filter: ActivityFilter, cursor: String?) async throws -> ActivityPage {
        let page = try await activity.notifications(filter: filter, cursor: cursor)
        let relationships = await actorRelationships(page.notifications.filter { $0.kind == .follow }.compactMap(\.actor?.id))
        let notifications = page.notifications.map { notification in
            var notification = notification
            if notification.kind == .follow { notification.actorRelationship = notification.actor.flatMap { relationships[$0.id] } }
            return notification
        }
        return ActivityPage(notifications: notifications, nextCursor: page.nextCursor)
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
