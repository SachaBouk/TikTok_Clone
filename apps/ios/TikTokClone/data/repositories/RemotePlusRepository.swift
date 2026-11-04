import Foundation
import TikTokAPI

// Abonnement « Plus » par l'API (module subscriptions, ADR-073).
struct RemotePlusRepository: PlusRepository {
    let client: Client

    func status() async throws -> PlusStatus {
        switch try await mappingErrors({ try await client.getMyPlusStatus() }) {
        case .ok(let ok): return PlusStatus(try ok.body.json)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension PlusStatus {
    // Mapping explicite (ADR-002).
    init(_ dto: Components.Schemas.PlusStatusResponse) {
        self.init(
            isActive: dto.active,
            period: dto.period.map { $0 == .annual ? .annual : .monthly },
            expiresAt: dto.expiresAt,
            willRenew: dto.willRenew
        )
    }
}
