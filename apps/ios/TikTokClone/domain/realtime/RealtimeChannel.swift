// Temps réel (ADR-011) vu par le domaine : événements poussés par l'API au compte connecté.
enum RealtimeUpdate: Equatable, Sendable {
    // Connexion (re)établie. Rien n'est rejoué après une coupure : relire l'état par l'API REST.
    case connected
    // Fin du transcodage d'une vidéo du compte : `ready` ou `failed`.
    case videoProcessed(OwnVideo)
    // Fin du traitement d'une story vidéo du compte (ADR-051) : `ready` ou `failed`.
    case storyProcessed(OwnVideo)
    // Nouvelle notification d'activité, avec le badge à jour.
    case notificationCreated(ActivityNotification, unreadCount: Int)
    // Badge seul (notifications lues sur un autre appareil).
    case unreadNotificationsChanged(Int)
    // Notifications supprimées (ADR-043) : réaction ou abonnement retirés, blocage, commentaire, vidéo ou compte supprimés.
    // `groups` : état recalculé des groupes touchés encore non vides ; badge à jour.
    case notificationsRemoved([RemovedActivity], groups: [ActivityGroup], unreadCount: Int)
    // Messagerie, avec les badges du compte connecté. Nouveau message (y compris envoyé depuis un autre appareil).
    case messageCreated(DirectMessage, MessagingBadges)
    // Message retiré par son expéditeur.
    case messageDeleted(conversationID: String, messageID: String, MessagingBadges)
    // Lecture : par l'autre (« Vu »), ou par le compte connecté sur un autre appareil.
    case conversationRead(conversationID: String, readerID: String, lastReadMessageID: String, MessagingBadges)
    // Demande acceptée : la conversation devient libre.
    case conversationAccepted(conversationID: String, MessagingBadges)
    // Conversation supprimée pour le compte connecté, ou demande refusée (sur cet appareil ou un autre).
    case conversationDeleted(conversationID: String, MessagingBadges)
    // L'autre participant est en train d'écrire.
    case typing(conversationID: String, userID: String)
    // Solde de jetons changé (achat crédité, remboursement).
    // Compteurs de son propre profil (ADR-045) : abonnement ou désabonnement, le sien ou celui d'un autre envers lui.
    case profileCountersChanged(followers: Int, following: Int)
    case walletUpdated(balance: Int, earned: Int)
}

// Port de la connexion temps réel. L'implémentation gère l'authentification, la détection des connexions
// mortes et la reconnexion ; `connect` et `disconnect` sont idempotents.
protocol RealtimeChannel: Sendable {
    // Un seul consommateur.
    var updates: AsyncStream<RealtimeUpdate> { get }
    func connect() async
    func disconnect() async
    // « En train d'écrire » : sans effet si la connexion n'est pas établie (rien n'est mis en attente).
    func sendTyping(conversationID: String) async
}
