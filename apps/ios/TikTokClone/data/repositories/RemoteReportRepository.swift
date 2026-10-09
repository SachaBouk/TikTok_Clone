import Foundation
import TikTokAPI

// Signalements par l'API (ADR-038) : mapping entité → DTO champ par champ.
struct RemoteReportRepository: ReportRepository {
    let client: Client

    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws {
        let (type, id): (Components.Schemas.ReportTargetType, String) =
            switch target {
            case .video(let id): (.video, id)
            case .comment(let id): (.comment, id)
            case .account(let id, _): (.account, id)
            case .message(let id): (.message, id)
            case .story(let id): (.story, id)
            case .live(let id): (.live, id)
            }
        let body = Components.Schemas.CreateReportRequest(targetType: type, targetId: id, reason: Self.reason(reason), details: details)
        switch try await mappingErrors({ try await client.createReport(body: .json(body)) }) {
        case .noContent: return
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .tooManyRequests(let error):
            let minutes = (max(1, error.headers.retryAfter ?? 60) + 59) / 60
            throw AppError.rejected("Trop de signalements envoyés. Réessaie dans \(minutes) min.")
        case .undocumented: throw AppError.unexpected
        }
    }

    private static func reason(_ reason: ReportReason) -> Components.Schemas.ReportReason {
        switch reason {
        case .spam: .spam
        case .harassment: .harassment
        case .hate: .hate
        case .violence: .violence
        case .sexual: .sexual
        case .impersonation: .impersonation
        case .other: .other
        }
    }
}
