// Erreurs des appels à l'API, vues par le domaine : indépendantes du transport (ADR-002).
enum AppError: Error, Equatable, Sendable {
    // Identifiant (email ou pseudo) ou mot de passe incorrect (le serveur ne dit pas lequel).
    case invalidCredentials
    // Requête refusée par l'API, avec son message (pseudo déjà pris, email invalide…).
    case rejected(String)
    // Inscription refusée car l'email ou le pseudo est déjà pris (409), avec le message de l'API.
    case alreadyRegistered(String)
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
    // Trop d'actions de ce type récemment (ADR-039) : réessayer après ce nombre de secondes.
    case tooManyActions(LimitedAction, retryAfter: Int)
    // Son propre compte, suspendu par un administrateur (ADR-037) : connexion refusée (403), sans motif.
    case accountSuspended
    // Solde de jetons insuffisant pour ce cadeau (402, ADR-050).
    case insufficientBalance
    // Le profil d'un compte suspendu n'est plus lisible (410).
    case profileSuspended
    // API injoignable (réseau, serveur arrêté).
    case network
    // Réponse inattendue.
    case unexpected

    // Message affiché à l'utilisateur.
    var message: String {
        switch self {
        case .invalidCredentials: "Identifiant ou mot de passe incorrect."
        case .rejected(let message), .alreadyRegistered(let message): message
        case .sessionExpired: "Ta session a expiré. Reconnecte-toi."
        case .blocked: "Action impossible : l’un de vous a bloqué l’autre."
        case .notFound: "Ce contenu n’est plus disponible."
        case .rateLimited(let seconds): "Trop de messages envoyés. Réessaie dans \(seconds) s."
        case .tooManyLoginAttempts(let seconds): "Trop de tentatives de connexion. Réessaie dans \(Self.delay(seconds))."
        case .tooManyActions(let action, let seconds): "\(action.tooMany) Réessaie dans \(Self.delay(seconds))."
        case .accountSuspended: "Ton compte est suspendu."
        case .insufficientBalance: "Solde insuffisant : recharge des jetons pour offrir ce cadeau."
        case .profileSuspended: "Ce compte a été suspendu."
        case .network: "Impossible de joindre le serveur. Vérifie ta connexion."
        case .unexpected: "Une erreur inattendue s’est produite."
        }
    }

    // « 45 s », « 12 min », « 3 h » : mêmes paliers que l'API.
    static func delay(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\((seconds + 59) / 60) min" }
        return "\((seconds + 3599) / 3600) h"
    }
}

// Actions limitées par l'API (ADR-039).
enum LimitedAction: Sendable {
    case signup, reactions, comments, follows, uploads, gifts, stories, storyLikes
    // Live (ADR-053) : lancements, messages du chat, cœurs.
    case lives, liveMessages, hearts

    var tooMany: String {
        switch self {
        case .signup: "Trop de comptes créés depuis cette connexion."
        case .reactions: "Trop de réactions en peu de temps."
        case .comments: "Trop de commentaires en peu de temps."
        case .follows: "Trop d’abonnements en peu de temps."
        case .uploads: "Trop de vidéos envoyées récemment."
        case .gifts: "Trop de cadeaux envoyés en peu de temps."
        case .stories: "Trop de stories publiées récemment."
        case .storyLikes: "Trop de likes en peu de temps."
        case .lives: "Trop de lives lancés aujourd’hui."
        case .liveMessages: "Trop de messages en peu de temps."
        case .hearts: "Trop de cœurs en peu de temps."
        }
    }
}
