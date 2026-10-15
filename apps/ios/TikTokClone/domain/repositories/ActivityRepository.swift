// Port du centre d'activité (module notifications).
protocol ActivityRepository: Sendable {
    // Boîte de réception : groupes, du plus récemment actif au plus ancien ; `kinds` vide : tous les types (ADR-058).
    func groups(kinds: [ActivityKind], cursor: String?) async throws -> ActivityGroupPage
    // Une ligne par notification, du plus récent au plus ancien ; `filter` : la liste complète d'un groupe.
    func notifications(filter: ActivityFilter?, cursor: String?) async throws -> ActivityPage
    // Badge : notifications non lues.
    func unreadCount() async throws -> Int
    // Marque lues `upToID` et les plus anciennes (toutes si nil) ; renvoie le nouveau badge.
    func markRead(upToID: String?) async throws -> Int
}
