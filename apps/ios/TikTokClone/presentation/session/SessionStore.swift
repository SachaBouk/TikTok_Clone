import Observation

// État de connexion de l'app, partagé par toutes les vues (environnement SwiftUI).
// Mode invité (ADR-010) : le feed est lisible sans compte ; le reste demande de se connecter.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case restoring
        case guest
        case signedIn(UserProfile)
        // Session enregistrée, API injoignable au lancement.
        case unavailable
    }

    private(set) var state: State = .restoring
    // Feuille de connexion affichée.
    var isPresentingSignIn = false
    // Message à afficher une fois (session expirée).
    var notice: String?

    private let restoreSession: RestoreSessionUseCase
    private let logout: LogoutUseCase

    init(restoreSession: RestoreSessionUseCase, logout: LogoutUseCase) {
        self.restoreSession = restoreSession
        self.logout = logout
    }

    var profile: UserProfile? {
        if case .signedIn(let profile) = state { profile } else { nil }
    }

    var isSignedIn: Bool { profile != nil }

    func restore() async {
        state = .restoring
        switch await restoreSession() {
        case .signedIn(let profile): state = .signedIn(profile)
        case .guest: state = .guest
        case .unavailable: state = .unavailable
        }
    }

    // Continuer sans attendre le serveur : en invité, la session enregistrée reste disponible.
    func continueAsGuest() {
        state = .guest
    }

    func signedIn(_ profile: UserProfile) {
        state = .signedIn(profile)
        isPresentingSignIn = false
    }

    func update(_ profile: UserProfile) {
        guard isSignedIn else { return }
        state = .signedIn(profile)
    }

    func signOut() async {
        await logout()
        state = .guest
    }

    // Refresh token refusé (expiré, révoqué, compte supprimé) : retour en invité, avec un message.
    func sessionExpired() {
        guard isSignedIn else { return }
        state = .guest
        notice = AppError.sessionExpired.message
    }

    func requestSignIn() {
        isPresentingSignIn = true
    }
}
