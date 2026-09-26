// Temps réel (ADR-011) vu par le domaine : événements poussés par l'API au compte connecté.
// Seuls ceux utilisés par l'app sont traduits ; les autres (activité, messagerie) viendront avec leurs écrans.
enum RealtimeUpdate: Equatable, Sendable {
    // Connexion (re)établie. Rien n'est rejoué après une coupure : relire l'état par l'API REST.
    case connected
    // Fin du transcodage d'une vidéo du compte : `ready` ou `failed`.
    case videoProcessed(OwnVideo)
}

// Port de la connexion temps réel. L'implémentation gère l'authentification, la détection des connexions
// mortes et la reconnexion ; `connect` et `disconnect` sont idempotents.
protocol RealtimeChannel: Sendable {
    // Un seul consommateur.
    var updates: AsyncStream<RealtimeUpdate> { get }
    func connect() async
    func disconnect() async
}
