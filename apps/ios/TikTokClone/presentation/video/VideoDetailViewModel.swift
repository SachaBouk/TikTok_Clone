import Foundation
import Observation

// Une vidéo seule, ouverte par un lien d'app (puis depuis une notification, l'historique…) : même page que le
// feed, avec lecture, vue comptée après 1 s et interactions.
@MainActor
@Observable
final class VideoDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(FeedVideo)
        case failed(String)
    }

    let videoID: String
    private(set) var state: State = .loading
    private(set) var isPaused = false

    private let loadVideo: LoadVideoUseCase
    private let recordView: RecordViewUseCase
    private let playback: any VideoPlayback
    private let session: SessionStore
    private let viewDelay: Duration
    private var viewTask: Task<Void, Never>?
    private var viewRecorded = false

    init(
        videoID: String,
        loadVideo: LoadVideoUseCase,
        recordView: RecordViewUseCase,
        playback: any VideoPlayback,
        session: SessionStore,
        viewDelay: Duration = ViewTracker.minimumWatchTime
    ) {
        self.videoID = videoID
        self.loadVideo = loadVideo
        self.recordView = recordView
        self.playback = playback
        self.session = session
        self.viewDelay = viewDelay
    }

    var video: FeedVideo? {
        if case .loaded(let video) = state { video } else { nil }
    }

    func start() async {
        guard video == nil else { return }
        state = .loading
        do {
            let video = try await loadVideo(id: videoID)
            state = .loaded(video)
            playback.keepLoaded([video])
            playback.play(video.id)
            scheduleView()
        } catch {
            state = .failed(AppError.from(error).message)
        }
    }

    func togglePause() {
        guard let video else { return }
        isPaused.toggle()
        if isPaused {
            viewTask?.cancel()
            playback.pauseAll()
        } else {
            playback.play(video.id)
            scheduleView()
        }
    }

    // Écran fermé : le feed reprend la main sur les lecteurs.
    func stop() {
        viewTask?.cancel()
        playback.pauseAll()
    }

    private func scheduleView() {
        viewTask?.cancel()
        guard session.isSignedIn, !viewRecorded, let video else { return }
        viewTask = Task { [viewDelay] in
            try? await Task.sleep(for: viewDelay)
            guard !Task.isCancelled, !isPaused else { return }
            if (try? await recordView(videoID: video.id)) != nil { viewRecorded = true }
        }
    }
}
