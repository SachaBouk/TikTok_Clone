import Foundation
import Observation

// Lives (ADR-053), un seul modèle pour toute l'app (AppContainer) : lives en cours des comptes suivis (rangée de la boîte
// de réception) et live en cours des profils ouverts (photo « EN DIRECT »). Un live terminé vu ici disparaît partout.
@MainActor
@Observable
final class LiveModel {
    private(set) var followingLives: [LiveStream] = []
    // Live en cours connu, par compte.
    private var byUser: [String: LiveStream] = [:]
    private var endedIDs: Set<String> = []

    private let loadFollowing: LoadFollowingLivesUseCase
    private let loadUserLive: LoadUserLiveUseCase
    private let session: SessionStore

    init(loadFollowing: LoadFollowingLivesUseCase, loadUserLive: LoadUserLiveUseCase, session: SessionStore) {
        self.loadFollowing = loadFollowing
        self.loadUserLive = loadUserLive
        self.session = session
    }

    // Rangée : à l'affichage de la boîte de réception et à chaque (re)connexion du temps réel. Un échec ne change rien.
    func refresh() async {
        guard session.isSignedIn, let lives = try? await loadFollowing() else { return }
        followingLives = lives.filter { !endedIDs.contains($0.id) }
        for live in followingLives { byUser[live.host.id] = live }
    }

    // Live en cours d'un compte (photo du profil) ; nil s'il n'en a pas.
    func live(of userID: String) -> LiveStream? {
        byUser[userID].flatMap { endedIDs.contains($0.id) ? nil : $0 }
    }

    // Profil ouvert : son live en cours est relu. Un échec ne change rien.
    func load(for user: UserSummary) async {
        guard let result = try? await loadUserLive(username: user.username) else { return }
        byUser[user.id] = result
    }

    // Live terminé (vu dans la salle, ou à l'ouverture) : retiré de la rangée et des profils.
    func ended(_ liveID: String) {
        endedIDs.insert(liveID)
        followingLives.removeAll { $0.id == liveID }
        byUser = byUser.filter { $0.value.id != liveID }
    }

    func reset() {
        followingLives = []
        byUser = [:]
        endedIDs = []
    }
}
