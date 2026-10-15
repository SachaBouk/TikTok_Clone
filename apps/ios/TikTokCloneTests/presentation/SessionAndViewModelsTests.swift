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
        let viewModel = LoginViewModel(
            login: LoginUseCase(auth: auth, profiles: FakeProfileRepository()), session: session, analytics: makeAnalytics())
        #expect(!viewModel.canSubmit)
        viewModel.identifier = " alice@example.com "
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
        let viewModel = LoginViewModel(
            login: LoginUseCase(auth: auth, profiles: FakeProfileRepository()), session: session, analytics: makeAnalytics())
        viewModel.identifier = "alice@example.com"
        viewModel.password = "mauvais"
        await viewModel.submit()
        #expect(viewModel.errorMessage == "Identifiant ou mot de passe incorrect.")
        #expect(!session.isSignedIn)
        #expect(!viewModel.isSubmitting)
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
}
