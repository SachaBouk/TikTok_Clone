import Foundation
import Observation

// Lecteur vertical : pages de l'API, lecture de la vidéo courante, préchargement des voisines, vues comptées
// après 1 s. Trois usages :
// - le feed principal (ADR-016) : à la fin d'une session, il repart sur un nouvel ordre, il ne s'arrête jamais ;
// - les feeds des abonnements (ADR-048) et des amis (ADR-054) : du plus récent au plus ancien, ils s'arrêtent à la fin ;
// - une liste (grille d'un profil, historique) : ouverte sur la vidéo touchée, elle s'arrête à la fin.
// Mesure d'audience (ADR-013) : visionnage de chaque vidéo, et expérience « invitation invité » (quelques vidéos
// regardées sans compte ouvrent la connexion, pour la variante).
@MainActor
@Observable
final class FeedViewModel {
    // Une vidéo peut revenir dans une session suivante : l'entrée a sa propre identité.
    struct Entry: Identifiable, Equatable {
        let id: String
        let video: FeedVideo
    }

    enum Mode {
        case endlessFeed
        case followingFeed
        case friendsFeed
        // Vidéos déjà chargées par la grille, et vidéo touchée.
        case list(FeedPage, startIndex: Int)
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

    private let loadPage: any VideoPageSource
    private let mode: Mode
    private let recordView: RecordViewUseCase
    private let playback: any VideoPlayback
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let viewDelay: Duration
    private let watch: WatchReporter

    private var nextCursor: String?
    private var generation = 0
    private var isLoadingMore = false
    // Onglet affiché et app au premier plan.
    private var isActive = true
    private var viewTracker = ViewTracker()
    private var viewTask: Task<Void, Never>?
    private var guestWatches = GuestWatchCounter()
    // Vidéos comptées pour l'invitation invité (lu par les tests : ils attendent qu'une vidéo soit comptée avant la suivante).
    var guestWatchedCount: Int { guestWatches.watched.count }

    init(
        loadPage: any VideoPageSource,
        recordView: RecordViewUseCase,
        playback: any VideoPlayback,
        session: SessionStore,
        analytics: AnalyticsModel,
        mode: Mode = .endlessFeed,
        viewDelay: Duration = ViewTracker.minimumWatchTime,
        now: @escaping () -> Date = Date.init
    ) {
        self.loadPage = loadPage
        self.mode = mode
        self.recordView = recordView
        self.playback = playback
        self.session = session
        self.analytics = analytics
        self.viewDelay = viewDelay
        let source: VideoSource =
            switch mode {
            case .endlessFeed: .feed
            case .followingFeed: .following
            case .friendsFeed: .friends
            case .list: .list
            }
        watch = WatchReporter(source: source, playback: playback, analytics: analytics, now: now)
    }

    // Les feeds des abonnements et des amis, et une liste, s'arrêtent à leur fin ; le feed principal repart sur un nouvel ordre.
    private var stopsAtEnd: Bool {
        if case .endlessFeed = mode { return false }
        return true
    }

    var currentVideo: FeedVideo? {
        entries.first { $0.id == currentEntryID }?.video
    }

    // Premier affichage : charge la première page si ce n'est pas déjà fait.
    func start() async {
        guard entries.isEmpty, loadState != .loading else { return }
        if case .list(let page, let startIndex) = mode {
            append(page)
            loadState = .loaded
            if entries.indices.contains(startIndex) { show(entries[startIndex].id) }
            return
        }
        await loadFirstPage()
    }

    // Vidéo supprimée (par son auteur) : retirée ; la suivante devient courante.
    // Comptes bloqués : leurs vidéos quittent le feed (l'API ne les renvoie plus).
    func remove(authorIDs: Set<String>) {
        remove(videoIDs: Set(entries.filter { authorIDs.contains($0.video.author.id) }.map(\.video.id)))
    }

    func remove(videoIDs: Set<String>) {
        guard entries.contains(where: { videoIDs.contains($0.video.id) }) else { return }
        let currentIndex = entries.firstIndex { $0.id == currentEntryID }
        let wasCurrentRemoved = currentVideo.map { videoIDs.contains($0.id) } ?? false
        entries.removeAll { videoIDs.contains($0.video.id) }
        guard wasCurrentRemoved else { return }
        currentEntryID = nil
        viewTask?.cancel()
        watch.discard()
        if let currentIndex, !entries.isEmpty {
            show(entries[min(currentIndex, entries.count - 1)].id)
        } else {
            playback.pauseAll()
        }
    }

    // Nouvelle session (tirer pour actualiser, connexion ou déconnexion : l'état des boutons change).
    func reload() async {
        viewTask?.cancel()
        watch.finish(.leave)
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
        // Avant de changer de lecteur : la position de la vidéo quittée est lue ici (moment du swipe).
        watch.finish(.swipe)
        playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
        if isActive {
            playback.play(video.id)
            watch.play(video)
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
            watch.pause()
            playback.pauseAll()
        } else if isActive {
            playback.play(video.id)
            watch.play(video)
            scheduleView(of: video)
        }
    }

    // Changement d'onglet ou passage en arrière-plan.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active {
            viewTask?.cancel()
            watch.finish(.leave)
            playback.pauseAll()
        } else if let video = currentVideo, !isPaused {
            // Une vidéo seule a pu occuper les lecteurs entre-temps : on recharge la fenêtre.
            if let index = entries.firstIndex(where: { $0.id == currentEntryID }) {
                playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
            }
            playback.play(video.id)
            watch.play(video)
            scheduleView(of: video)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, loadState == .loaded, !entries.isEmpty else { return }
        if stopsAtEnd, nextCursor == nil { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        // Fin de session : nouvelle session, nouvel ordre (les vidéos peuvent revenir).
        if nextCursor == nil { generation += 1 }
        do {
            append(try await fetchPage(cursor: nextCursor))
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
            append(try await fetchPage(cursor: nil))
            loadState = .loaded
            if let first = entries.first { show(first.id) }
        } catch {
            loadState = .failed(AppError.from(error).message)
        }
    }

    private func fetchPage(cursor: String?) async throws -> FeedPage {
        try await EmptyPages.fetch(cursor, load: { try await loadPage.page(cursor: $0) }, isEmpty: { $0.videos.isEmpty }, next: { $0.nextCursor })
    }

    private func append(_ page: FeedPage) {
        let generation = generation
        entries += page.videos.map { Entry(id: "\(generation)-\($0.id)", video: $0) }
        nextCursor = page.nextCursor
    }

    // Vue comptée après `viewDelay` de lecture continue, pour un compte connecté, une fois par session du feed.
    // En invité : vidéo comptée pour l'expérience « invitation invité ».
    private func scheduleView(of video: FeedVideo) {
        viewTask?.cancel()
        guard session.isSignedIn else {
            scheduleGuestWatch(of: video)
            return
        }
        guard viewTracker.needsRecording(video.id) else { return }
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

    private func scheduleGuestWatch(of video: FeedVideo) {
        viewTask = Task { [viewDelay] in
            try? await Task.sleep(for: viewDelay)
            guard !Task.isCancelled, currentVideo?.id == video.id, !isPaused, !session.isSignedIn else { return }
            if guestWatches.record(video.id), analytics.shouldPromptGuest() {
                session.requestSignIn(message: GuestPromptExperiment.message)
            }
        }
    }
}
