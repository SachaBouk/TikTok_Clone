import Foundation
import TikTokAPI

// Jeton de Participant du Live commun (ADR-079) : demandé par le SDK d'echimine à chaque connexion, jamais gardé.
struct RemoteLiveTokenRepository: LiveTokenRepository {
    let client: Client

    func participantToken() async throws -> String {
        switch try await mappingErrors({ try await client.createLiveParticipantToken() }) {
        case .ok(let ok): return try ok.body.json.token
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.sessionExpired
        case .serviceUnavailable: throw AppError.unexpected
        case .undocumented: throw AppError.unexpected
        }
    }
}
