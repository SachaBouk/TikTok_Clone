import Foundation
import Observation

// Feuille de signalement (ADR-038), en étapes comme TikTok : un motif de la liste, sa page (explication, précision
// facultative, « Envoyer »), puis « Merci pour ton signalement ». Rien n'est masqué ensuite (décision d'un administrateur),
// mais l'écran de remerciement propose de bloquer l'auteur d'une vidéo ou d'un commentaire (`author`).
@MainActor
@Observable
final class ReportViewModel {
    enum State: Equatable {
        case editing
        case sending
        case sent
    }

    enum BlockState: Equatable {
        case idle
        case blocking
        case blocked
    }

    let target: ReportTarget
    var reason: ReportReason?
    var details = ""
    private(set) var state: State = .editing
    var errorMessage: String?
    // Auteur du contenu signalé (vidéo, commentaire), proposé au blocage après l'envoi ; nil : rien à proposer.
    let author: UserSummary?
    private(set) var blockState: BlockState = .idle

    private let sendReport: SendReportUseCase
    private let setBlocked: SetBlockedUseCase?
    private let interactions: VideoInteractionsModel?
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(
        target: ReportTarget,
        sendReport: SendReportUseCase,
        session: SessionStore,
        analytics: AnalyticsModel,
        author: UserSummary? = nil,
        setBlocked: SetBlockedUseCase? = nil,
        interactions: VideoInteractionsModel? = nil
    ) {
        self.target = target
        self.sendReport = sendReport
        self.session = session
        self.analytics = analytics
        self.author = setBlocked == nil ? nil : author
        self.setBlocked = setBlocked
        self.interactions = interactions
    }

    // Blocage de l'auteur depuis l'écran de remerciement : ses contenus disparaissent des écrans (comme depuis son profil).
    func blockAuthor() async {
        guard let author, let setBlocked, blockState == .idle else { return }
        blockState = .blocking
        do {
            try await setBlocked(true, username: author.username)
            interactions?.blocked(author.id)
            blockState = .blocked
        } catch {
            blockState = .idle
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() } else { errorMessage = error.message }
        }
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
