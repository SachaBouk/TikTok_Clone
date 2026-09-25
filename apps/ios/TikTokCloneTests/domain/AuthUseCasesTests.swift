import Testing
@testable import TikTokClone

@Suite("Cas d'usage de l'authentification")
struct AuthUseCasesTests {
    @Test("reprise : sans session → invité")
    func restoreGuest() async {
        let auth = FakeAuthRepository(hasSession: false)
        #expect(await RestoreSessionUseCase(auth: auth, profiles: FakeProfileRepository())() == .guest)
    }

    @Test("reprise : session valide → connecté avec le profil")
    func restoreSignedIn() async {
        let auth = FakeAuthRepository(hasSession: true)
        #expect(await RestoreSessionUseCase(auth: auth, profiles: FakeProfileRepository())() == .signedIn(.alice))
    }

    @Test("reprise : session expirée → invité, session oubliée")
    func restoreExpired() async {
        let auth = FakeAuthRepository(hasSession: true)
        let result = await RestoreSessionUseCase(auth: auth, profiles: FakeProfileRepository(.failure(.sessionExpired)))()
        #expect(result == .guest)
        #expect(auth.state.withLock { $0.logoutCount } == 1)
    }

    @Test("reprise : API injoignable → indisponible, session gardée")
    func restoreOffline() async {
        let auth = FakeAuthRepository(hasSession: true)
        let result = await RestoreSessionUseCase(auth: auth, profiles: FakeProfileRepository(.failure(.network)))()
        #expect(result == .unavailable)
        #expect(auth.hasStoredSession())
    }

    @Test("inscription : règles vérifiées avant l'envoi, textes nettoyés", arguments: [
        ("pas-un-email", "alice", "Alice", "motdepasse", "Adresse email invalide."),
        ("a@b.c", "Alice!", "Alice", "motdepasse", "Pseudo : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »."),
        ("a@b.c", "me", "Alice", "motdepasse", "Ce pseudo n’est pas disponible."),
        ("a@b.c", "alice", "   ", "motdepasse", "Nom : 1 à 50 caractères."),
        ("a@b.c", "alice", "Alice", "court", "Mot de passe : 8 caractères au minimum."),
    ])
    func registrationRules(email: String, username: String, displayName: String, password: String, message: String) async {
        let auth = FakeAuthRepository()
        let register = RegisterUseCase(auth: auth, profiles: FakeProfileRepository())
        await #expect(throws: AuthError.rejected(message)) {
            try await register(Registration(email: email, password: password, username: username, displayName: displayName))
        }
        #expect(auth.state.withLock { $0.registrations.isEmpty })
    }

    @Test("inscription valide : envoyée nettoyée, puis profil lu")
    func registerValid() async throws {
        let auth = FakeAuthRepository()
        let profile = try await RegisterUseCase(auth: auth, profiles: FakeProfileRepository())(
            Registration(email: " a@b.c ", password: "motdepasse", username: "alice", displayName: "  Alice ")
        )
        #expect(profile == .alice)
        #expect(auth.state.withLock { $0.registrations } == [Registration(email: "a@b.c", password: "motdepasse", username: "alice", displayName: "Alice")])
    }
}
