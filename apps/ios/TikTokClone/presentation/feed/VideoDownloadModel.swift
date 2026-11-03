import Foundation
import Observation

// Téléchargement d'une vidéo dans Photos (ADR-067), un à la fois pour toute l'app (`AppContainer.downloads`) : progression
// affichée par-dessus le lecteur, puis « Enregistrée dans Photos » ou le message d'erreur, effacé après `messageDuration`.
@MainActor
@Observable
final class VideoDownloadModel {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case saved
        case failed(String)
    }

    private(set) var state = State.idle
    private let download: DownloadVideoUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel?
    private let messageDuration: Duration

    init(download: DownloadVideoUseCase, session: SessionStore, analytics: AnalyticsModel?, messageDuration: Duration = .seconds(2)) {
        self.download = download
        self.session = session
        self.analytics = analytics
        self.messageDuration = messageDuration
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    // Invité : la connexion s'ouvre. Un téléchargement déjà en cours est gardé.
    func start(_ video: FeedVideo) async {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        guard !isDownloading else { return }
        state = .downloading(0)
        do {
            try await download(videoID: video.id) { fraction in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            state = .saved
            analytics?.track(.videoDownloaded(videoID: video.id))
        } catch AppError.sessionExpired {
            state = .idle
            session.sessionExpired()
            return
        } catch AppError.notFound {
            state = .failed("Cette vidéo n’est plus disponible.")
        } catch {
            state = .failed(AppError.from(error).message)
        }
        let shown = state
        try? await Task.sleep(for: messageDuration)
        if state == shown { state = .idle }
    }
}
