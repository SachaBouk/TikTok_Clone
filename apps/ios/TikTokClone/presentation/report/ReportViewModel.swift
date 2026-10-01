import Foundation
import Observation

// Feuille de signalement (ADR-038) : un motif de la liste, une précision facultative, puis la confirmation
// « Merci, ton signalement sera examiné. ». Rien n'est masqué ensuite (décision d'un administrateur).
@MainActor
@Observable
final class ReportViewModel {
    enum State: Equatable {
        case editing
        case sending
        case sent
    }

    let target: ReportTarget
    var reason: ReportReason?
    var details = ""
    private(set) var state: State = .editing
    var errorMessage: String?

    private let sendReport: SendReportUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(target: ReportTarget, sendReport: SendReportUseCase, session: SessionStore, analytics: AnalyticsModel) {
        self.target = target
        self.sendReport = sendReport
        self.session = session
        self.analytics = analytics
    }

    var remainingCharacters: Int {
        ReportRules.maxDetailsLength - details.count
    }

    var canSend: Bool {
        reason != nil && state == .editing && remainingCharacters >= 0
    }

    func send() async {
        guard canSend, let reason else { return }
        state = .sending
        do {
            try await sendReport(target, reason: reason, details: details)
            state = .sent
            analytics.track(.reportSubmitted(target: target, reason: reason))
        } catch {
            state = .editing
            let error = AppError.from(error)
            if error == .sessionExpired {
                session.sessionExpired()
            } else if error == .notFound {
                errorMessage = "Ce contenu n’est plus disponible."
            } else {
                errorMessage = error.message
            }
        }
    }
}
