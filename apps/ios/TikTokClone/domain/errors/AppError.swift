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
    // Trop d'échecs de connexion récents pour cet email ou cette adresse (ADR-030) : réessayer après ce nombre de secondes.
    case tooManyLoginAttempts(retryAfter: Int)
    // Son propre compte, suspendu par un administrateur (ADR-037) : connexion refusée (403), sans motif.
    case accountSuspended
    // Le profil d'un compte suspendu n'est plus lisible (410).
    case profileSuspended
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
        case .tooManyLoginAttempts(let seconds):
            "Trop de tentatives de connexion. Réessaie dans \(seconds < 60 ? "\(seconds) s" : "\((seconds + 59) / 60) min")."
        case .accountSuspended: "Ton compte est suspendu."
        case .profileSuspended: "Ce compte a été suspendu."
        case .network: "Impossible de joindre le serveur. Vérifie ta connexion."
        case .unexpected: "Une erreur inattendue s’est produite."
        }
    }
}
