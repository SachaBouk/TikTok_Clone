// Erreurs des appels à l'API, vues par le domaine : indépendantes du transport (ADR-002).
enum AppError: Error, Equatable, Sendable {
    // Email ou mot de passe incorrect (le serveur ne dit pas lequel).
    case invalidCredentials
    // Requête refusée par l'API, avec son message (pseudo déjà pris, email invalide…).
    case rejected(String)
    // Session expirée ou révoquée, ou compte supprimé : il faut se reconnecter.
    case sessionExpired
    // L'un des deux comptes a bloqué l'autre (403).
    case blocked
    // Vidéo, commentaire ou compte disparu entre-temps (404).
    case notFound
    // Trop de requêtes (limite d'envoi des messages) : réessayer après ce nombre de secondes.
    case rateLimited(retryAfter: Int)
    // API injoignable (réseau, serveur arrêté).
    case network
    // Réponse inattendue.
    case unexpected

    // Message affiché à l'utilisateur.
    var message: String {
        switch self {
        case .invalidCredentials: "Email ou mot de passe incorrect."
        case .rejected(let message): message
        case .sessionExpired: "Ta session a expiré. Reconnecte-toi."
        case .blocked: "Action impossible : l’un de vous a bloqué l’autre."
        case .notFound: "Ce contenu n’est plus disponible."
        case .rateLimited(let seconds): "Trop de messages envoyés. Réessaie dans \(seconds) s."
        case .network: "Impossible de joindre le serveur. Vérifie ta connexion."
        case .unexpected: "Une erreur inattendue s’est produite."
        }
    }
}
