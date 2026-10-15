// Cas d'usage de l'inscription par étapes (ADR-055).

struct CheckUsernameUseCase: Sendable {
    let signup: any SignupRepository

    // Règles vérifiées sur place, sans appel : seule la disponibilité d'un pseudo valide est demandée à l'API.
    func callAsFunction(_ username: String) async throws -> UsernameAvailability {
        if username.wholeMatch(of: RegistrationRules.usernamePattern) == nil { return .invalid }
        if RegistrationRules.reservedUsernames.contains(username) { return .reserved }
        return try await signup.usernameAvailability(username)
    }
}

struct LoadInterestCatalogUseCase: Sendable {
    let signup: any SignupRepository

    func callAsFunction() async throws -> [Interest] {
        try await signup.interestCatalog()
    }
}

struct LoadMyInterestsUseCase: Sendable {
    let signup: any SignupRepository

    func callAsFunction() async throws -> [String] {
        try await signup.myInterests()
    }
}

struct SaveInterestsUseCase: Sendable {
    let signup: any SignupRepository

    func callAsFunction(_ codes: [String]) async throws -> [String] {
        try await signup.setMyInterests(codes)
    }
}
