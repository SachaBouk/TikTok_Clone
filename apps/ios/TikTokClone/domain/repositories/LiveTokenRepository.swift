// Jeton de Participant du Live commun (ADR-079), signé par l'API pour le compte connecté (`POST /live/participant-token`).
protocol LiveTokenRepository: Sendable {
    func participantToken() async throws -> String
}
