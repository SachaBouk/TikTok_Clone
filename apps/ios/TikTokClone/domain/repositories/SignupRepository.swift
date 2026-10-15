// Port de l'inscription par étapes (ADR-055) : disponibilité du pseudo, centres d'intérêt.
protocol SignupRepository: Sendable {
    func usernameAvailability(_ username: String) async throws -> UsernameAvailability
    func interestCatalog() async throws -> [Interest]
    // Codes du compte connecté, dans l'ordre du catalogue.
    func myInterests() async throws -> [String]
    // Remplace la liste ; renvoie celle enregistrée.
    func setMyInterests(_ codes: [String]) async throws -> [String]
}
