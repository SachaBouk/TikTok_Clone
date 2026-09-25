// Données d'inscription par email (ADR-010). Sign in with Apple viendra avec un compte Apple Developer.
struct Registration: Equatable, Sendable {
    let email: String
    let password: String
    let username: String
    let displayName: String
}
