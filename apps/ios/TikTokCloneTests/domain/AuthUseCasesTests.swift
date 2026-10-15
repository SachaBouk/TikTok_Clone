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

    static let adult = BirthDate(year: 2000, month: 2, day: 18)
    static let today = BirthDate(year: 2026, month: 10, day: 15)

    @Test(
        "inscription : règles vérifiées avant l'envoi (ADR-055)",
        arguments: [
            ("pas-un-email", "alice", "motdepasse1", adult, "Adresse email invalide."),
            ("a@b.c", "Alice!", "motdepasse1", adult, "2 à 24 caractères : lettres minuscules, chiffres, « . » et « _ »."),
            ("a@b.c", "me", "motdepasse1", adult, "Ce pseudo n’est pas disponible."),
            ("a@b.c", "alice", "motdepasse", adult, "Mot de passe : 8 caractères au minimum, avec au moins une lettre et un chiffre."),
            ("a@b.c", "alice", "court1", adult, "Mot de passe : 8 caractères au minimum, avec au moins une lettre et un chiffre."),
            (
                "a@b.c", "alice", "motdepasse1", BirthDate(year: 2013, month: 10, day: 16),
                "Désolé, il faut avoir au moins 13 ans pour créer un compte."
            ),
            ("a@b.c", "alice", "motdepasse1", BirthDate(year: 2027, month: 1, day: 1), "Date de naissance invalide."),
        ])
    func registrationRules(email: String, username: String, password: String, birthDate: BirthDate, message: String) async {
        let auth = FakeAuthRepository()
        let register = RegisterUseCase(auth: auth, profiles: FakeProfileRepository(), today: { Self.today })
        await #expect(throws: AppError.rejected(message)) {
            try await register(Registration(email: email, password: password, username: username, birthDate: birthDate))
        }
        #expect(auth.state.withLock { $0.registrations.isEmpty })
    }

    @Test("inscription valide : envoyée nettoyée, sans nom (le pseudo par défaut), puis profil lu")
    func registerValid() async throws {
        let auth = FakeAuthRepository()
        let birthDate = BirthDate(year: 2013, month: 10, day: 15)
        let profile = try await RegisterUseCase(auth: auth, profiles: FakeProfileRepository(), today: { Self.today })(
            Registration(email: " a@b.c ", password: "motdepasse1", username: "alice", displayName: "  ", birthDate: birthDate)
        )
        #expect(profile == .alice)
        #expect(
            auth.state.withLock { $0.registrations } == [
                Registration(email: "a@b.c", password: "motdepasse1", username: "alice", displayName: nil, birthDate: birthDate)
            ])
    }
}
