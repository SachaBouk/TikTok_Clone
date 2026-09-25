import Testing
@testable import TikTokClone

@MainActor
@Suite("SessionStore et ViewModels")
struct SessionAndViewModelsTests {
    @Test("connexion réussie : session connectée, feuille fermée")
    func loginSuccess() async {
        let auth = FakeAuthRepository()
        let session = makeSession(auth: auth)
        session.requestSignIn()
        let viewModel = LoginViewModel(login: LoginUseCase(auth: auth, profiles: FakeProfileRepository()), session: session)
        #expect(!viewModel.canSubmit)
        viewModel.email = " alice@example.com "
        viewModel.password = "motdepasse"
        #expect(viewModel.canSubmit)

        await viewModel.submit()
        #expect(session.profile == .alice)
        #expect(!session.isPresentingSignIn)
        #expect(auth.state.withLock { $0.logins } == ["alice@example.com"])
    }

    @Test("connexion refusée : message affiché, toujours invité")
    func loginFailure() async {
        let auth = FakeAuthRepository(loginError: .invalidCredentials)
        let session = makeSession(auth: auth)
        let viewModel = LoginViewModel(login: LoginUseCase(auth: auth, profiles: FakeProfileRepository()), session: session)
        viewModel.email = "alice@example.com"
        viewModel.password = "mauvais"
        await viewModel.submit()
        #expect(viewModel.errorMessage == "Email ou mot de passe incorrect.")
        #expect(!session.isSignedIn)
        #expect(!viewModel.isSubmitting)
    }

    @Test("inscription : pseudo mis en minuscules, message de l'API affiché")
    func register() async {
        let auth = FakeAuthRepository(registerError: .rejected("Le pseudo @alice est déjà pris"))
        let session = makeSession(auth: auth)
        let viewModel = RegisterViewModel(register: RegisterUseCase(auth: auth, profiles: FakeProfileRepository()), session: session)
        viewModel.username = "Alice"
        viewModel.normalizeUsername()
        #expect(viewModel.username == "alice")
        viewModel.email = "alice@example.com"
        viewModel.password = "motdepasse"
        viewModel.displayName = "Alice"
        await viewModel.submit()
        #expect(viewModel.errorMessage == "Le pseudo @alice est déjà pris")
    }

    @Test("session expirée : retour en invité avec un message, une seule fois")
    func sessionExpired() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        #expect(session.profile == .alice)
        session.sessionExpired()
        #expect(session.state == .guest)
        #expect(session.notice == "Ta session a expiré. Reconnecte-toi.")
        session.notice = nil
        session.sessionExpired()
        #expect(session.notice == nil)
    }

    @Test("déconnexion : session oubliée, retour en invité")
    func signOut() async {
        let auth = FakeAuthRepository(hasSession: true)
        let session = makeSession(auth: auth)
        await session.restore()
        let viewModel = ProfileViewModel(getMyProfile: GetMyProfileUseCase(profiles: FakeProfileRepository()), session: session)
        await viewModel.signOut()
        #expect(session.state == .guest)
        #expect(!auth.hasStoredSession())
    }

    @Test("profil : actualisation, et session expirée détectée")
    func profileRefresh() async {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let updated = UserProfile(id: UserProfile.alice.id, username: "alice", displayName: "Alice M.", avatarURL: nil, bio: nil,
                                  followersCount: 4, followingCount: 1, createdAt: UserProfile.alice.createdAt)
        await ProfileViewModel(getMyProfile: GetMyProfileUseCase(profiles: FakeProfileRepository(.success(updated))), session: session).refresh()
        #expect(session.profile?.displayName == "Alice M.")

        await ProfileViewModel(getMyProfile: GetMyProfileUseCase(profiles: FakeProfileRepository(.failure(.sessionExpired))), session: session).refresh()
        #expect(session.state == .guest)
    }
}
