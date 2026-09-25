// Port de l'authentification (ADR-002, ADR-010). L'implémentation garde les tokens (Keychain) :
// le domaine ne les manipule jamais.
protocol AuthRepository: Sendable {
    // Lève AuthError.invalidCredentials, .rejected, .network…
    func login(email: String, password: String) async throws
    func register(_ registration: Registration) async throws
    // Oublie la session localement, puis la révoque côté serveur si possible. Ne lève jamais.
    func logout() async
    // Une session est-elle enregistrée sur l'appareil ?
    func hasStoredSession() -> Bool
}
