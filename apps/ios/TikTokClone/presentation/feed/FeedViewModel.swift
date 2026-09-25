import Foundation
import Observation

// Feed principal (ADR-016) : pages de l'API, lecture de la vidéo courante, préchargement des voisines,
// vues comptées après 1 s. À la fin d'une session, le feed repart sur un nouvel ordre : il ne s'arrête jamais.
@MainActor
@Observable
final class FeedViewModel {
    // Une vidéo peut revenir dans une session suivante : l'entrée a sa propre identité.
    struct Entry: Identifiable, Equatable {
        let id: String
        let video: FeedVideo
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var entries: [Entry] = []
    private(set) var loadState: LoadState = .idle
    private(set) var currentEntryID: String?
    private(set) var isPaused = false
    // Incrémenté à chaque rechargement : la vue recrée alors sa ScrollView, qui repart en haut, sur la vidéo
    // courante. Sans cela, elle garderait sa position (2e vidéo) pendant que la 1re est lue.
    // La fin de session (loadMore) ne l'incrémente pas : les vidéos s'ajoutent à la suite.
    private(set) var reloadCount = 0

    private let loadPage: LoadFeedPageUseCase
    private let recordView: RecordViewUseCase
    private let playback: any VideoPlayback
    private let session: SessionStore
    private let viewDelay: Duration

    private var nextCursor: String?
    private var generation = 0
    private var isLoadingMore = false
    // Onglet affiché et app au premier plan.
    private var isActive = true
    private var viewTracker = ViewTracker()
    private var viewTask: Task<Void, Never>?

    init(
        loadPage: LoadFeedPageUseCase,
        recordView: RecordViewUseCase,
        playback: any VideoPlayback,
        session: SessionStore,
        viewDelay: Duration = ViewTracker.minimumWatchTime
    ) {
        self.loadPage = loadPage
        self.recordView = recordView
        self.playback = playback
        self.session = session
        self.viewDelay = viewDelay
    }

    var currentVideo: FeedVideo? {
        entries.first { $0.id == currentEntryID }?.video
    }

    // Premier affichage : charge la première page si ce n'est pas déjà fait.
    func start() async {
        guard entries.isEmpty, loadState != .loading else { return }
        await loadFirstPage()
    }

    // Nouvelle session (tirer pour actualiser, connexion ou déconnexion : l'état des boutons change).
    func reload() async {
        viewTask?.cancel()
        playback.pauseAll()
        entries = []
        currentEntryID = nil
        nextCursor = nil
        generation += 1
        reloadCount += 1
        viewTracker = ViewTracker()
        await loadFirstPage()
    }

    // La vidéo `entryID` devient la vidéo affichée (défilement).
    func show(_ entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        currentEntryID = entryID
        isPaused = false
        let video = entries[index].video
        playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
        if isActive {
            playback.play(video.id)
            scheduleView(of: video)
        }
        if PreloadPolicy.shouldLoadMore(currentIndex: index, count: entries.count) {
            Task { await loadMore() }
        }
    }

    // Toucher la vidéo : pause ou reprise.
    func togglePause() {
        guard let video = currentVideo else { return }
        isPaused.toggle()
        if isPaused {
            viewTask?.cancel()
            playback.pauseAll()
        } else if isActive {
            playback.play(video.id)
            scheduleView(of: video)
        }
    }

    // Changement d'onglet ou passage en arrière-plan.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active {
            viewTask?.cancel()
            playback.pauseAll()
        } else if let video = currentVideo, !isPaused {
            // Une vidéo seule a pu occuper les lecteurs entre-temps : on recharge la fenêtre.
            if let index = entries.firstIndex(where: { $0.id == currentEntryID }) {
                playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
            }
            playback.play(video.id)
            scheduleView(of: video)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, loadState == .loaded, !entries.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        // Fin de session : nouvelle session, nouvel ordre (les vidéos peuvent revenir).
        if nextCursor == nil { generation += 1 }
        do {
            append(try await loadPage(cursor: nextCursor))
            // La fenêtre de préchargement peut maintenant inclure la vidéo suivante.
            if let currentEntryID, let index = entries.firstIndex(where: { $0.id == currentEntryID }) {
                playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
            }
        } catch {
            // Silencieux : un prochain défilement réessaiera.
        }
    }

    private func loadFirstPage() async {
        loadState = .loading
        do {
            append(try await loadPage(cursor: nil))
            loadState = .loaded
            if let first = entries.first { show(first.id) }
        } catch {
            loadState = .failed(AppError.from(error).message)
        }
    }

    private func append(_ page: FeedPage) {
        let generation = generation
        entries += page.videos.map { Entry(id: "\(generation)-\($0.id)", video: $0) }
        nextCursor = page.nextCursor
    }

    // Vue comptée après `viewDelay` de lecture continue, pour un compte connecté, une fois par session du feed.
    private func scheduleView(of video: FeedVideo) {
        viewTask?.cancel()
        guard session.isSignedIn, viewTracker.needsRecording(video.id) else { return }
        viewTask = Task { [viewDelay] in
            try? await Task.sleep(for: viewDelay)
            guard !Task.isCancelled, currentVideo?.id == video.id, !isPaused else { return }
            do {
                try await recordView(videoID: video.id)
                viewTracker.markRecorded(video.id)
            } catch AppError.sessionExpired {
                session.sessionExpired()
            } catch {
                // Réseau : la vue sera retentée au prochain affichage.
            }
        }
    }
}
