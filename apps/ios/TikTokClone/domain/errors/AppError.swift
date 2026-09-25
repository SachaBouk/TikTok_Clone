// Erreurs des appels à l'API, vues par le domaine : indépendantes du transport (ADR-002).
enum AppError: Error, Equatable, Sendable {
    // Email ou mot de passe incorrect (le serveur ne dit pas lequel).
    case invalidCredentials
    // Requête refusée par l'API, avec son message (pseudo déjà pris, email invalide…).
    case rejected(String)
    // Session expirée ou révoquée, ou compte supprimé : il faut se reconnecter.
    case sessionExpired
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
        case .network: "Impossible de joindre le serveur. Vérifie ta connexion."
        case .unexpected: "Une erreur inattendue s’est produite."
        }
    }
}
