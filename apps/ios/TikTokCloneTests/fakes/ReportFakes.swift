import Foundation
import Synchronization

@testable import TikTokClone

// Signalements en mémoire : ce qui a été envoyé, et une erreur à lever.
final class FakeReportRepository: ReportRepository {
    struct Sent: Equatable {
        let target: ReportTarget
        let reason: ReportReason
        let details: String?
    }

    private let state = Mutex<(sent: [Sent], error: AppError?)>(([], nil))
    var sent: [Sent] { state.withLock { $0.sent } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.sent.append(Sent(target: target, reason: reason, details: details))
        }
    }
}
