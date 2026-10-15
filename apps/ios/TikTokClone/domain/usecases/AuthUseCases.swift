// Cas d'usage de l'authentification (ADR-002). Connexion et inscription se terminent par la lecture
// du profil : l'app a besoin du compte connecté pour afficher son profil et ses boutons.

struct LoginUseCase: Sendable {
    let auth: any AuthRepository
    let profiles: any ProfileRepository

    // `identifier` : email ou pseudo (ADR-055).
    func callAsFunction(identifier: String, password: String) async throws -> UserProfile {
        try await auth.login(identifier: identifier.trimmingCharacters(in: .whitespaces), password: password)
        return try await profiles.myProfile()
    }
}

struct RegisterUseCase: Sendable {
    let auth: any AuthRepository
    let profiles: any ProfileRepository

    func callAsFunction(_ registration: Registration) async throws -> UserProfile {
        if let problem = RegistrationRules.problem(with: registration) { throw AppError.rejected(problem) }
        try await auth.register(
            Registration(
                email: registration.email.trimmingCharacters(in: .whitespaces),
                password: registration.password,
                username: registration.username,
                displayName: registration.displayName.trimmingCharacters(in: .whitespaces)
            ))
        return try await profiles.myProfile()
    }
}

struct LogoutUseCase: Sendable {
    let auth: any AuthRepository

    func callAsFunction() async {
        await auth.logout()
    }
}

// Au lancement : reprend la session enregistrée, s'il y en a une.
enum RestoredSession: Equatable, Sendable {
    case signedIn(UserProfile)
    case guest
    // Session enregistrée, mais API injoignable : on ne sait pas encore si elle est valide.
    case unavailable
}

struct RestoreSessionUseCase: Sendable {
    let auth: any AuthRepository
    let profiles: any ProfileRepository

    func callAsFunction() async -> RestoredSession {
        guard auth.hasStoredSession() else { return .guest }
        do {
            return .signedIn(try await profiles.myProfile())
        } catch AppError.network {
            return .unavailable
        } catch {
            // Session expirée, révoquée ou compte supprimé : on repart en invité, sans session enregistrée.
            await auth.logout()
            return .guest
        }
    }
}

struct GetMyProfileUseCase: Sendable {
    let profiles: any ProfileRepository

    func callAsFunction() async throws -> UserProfile {
        try await profiles.myProfile()
    }
}
