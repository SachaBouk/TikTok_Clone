import Foundation

// Profil du compte connecté tenu à jour hors de son écran (ADR-045) : compteurs d'abonnés et d'abonnements reçus en
// direct (`profileCountersChanged`), profil relu à chaque (re)connexion du temps réel (rien n'est rejoué après une
// coupure). L'onglet Profil affiche `session.profile` : il suit sans rien recharger.
@MainActor
final class OwnProfileSync {
    private let session: SessionStore
    private let getMyProfile: GetMyProfileUseCase

    init(session: SessionStore, getMyProfile: GetMyProfileUseCase) {
        self.session = session
        self.getMyProfile = getMyProfile
    }

    // (Re)connexion : relu par l'API. Échec (réseau) : la prochaine reconnexion réessaiera.
    func refresh() async {
        guard session.isSignedIn, let profile = try? await getMyProfile() else { return }
        // Déconnecté ou compte changé pendant la requête : sans effet.
        guard session.profile?.id == profile.id else { return }
        session.update(profile)
    }

    // Événement `profileCountersChanged` : valeurs à jour de l'API.
    func countersChanged(followers: Int, following: Int) {
        guard let profile = session.profile else { return }
        session.update(profile.with(followersCount: followers, followingCount: following))
    }
}
