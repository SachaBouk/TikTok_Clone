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

    // Une page du lecteur : une vidéo, ou le carrousel de comptes suggérés (feed principal, `SuggestionCarouselRules`).
    enum Page: Identifiable, Equatable {
        case video(Entry)
        case suggestions(id: String)

        var id: String {
            switch self {
            case .video(let entry): entry.id
            case .suggestions(let id): id
            }
        }
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
    // Page affichée : une vidéo (`Entry.id`) ou le carrousel (`Page.suggestions`).
    private(set) var currentEntryID: String?
    // Carrousel de comptes suggérés affiché (compte connecté avec des suggestions à voir, feed principal seulement).
    private(set) var showsSuggestions = false
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
    // Vidéos ajoutées depuis le dernier rechargement, et entrées après lesquelles le carrousel s'insère.
    private var videoCount = 0
    private var suggestionAnchors: [String] = []
    // Onglet affiché et app au premier plan.
    private var isActive = true
    // Vidéos masquées par le voile d'un signalement : jamais lues tant qu'il est là.
    private var maskedVideoIDs: Set<String> = []
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

    // Pages du lecteur : les vidéos, et le carrousel après ses ancres quand il est affiché.
    var pages: [Page] {
        guard showsSuggestions, !suggestionAnchors.isEmpty else { return entries.map { .video($0) } }
        let anchors = Set(suggestionAnchors)
        var pages: [Page] = []
        for entry in entries {
            pages.append(.video(entry))
            if anchors.contains(entry.id) { pages.append(.suggestions(id: Self.suggestionsID(after: entry.id))) }
        }
        return pages
    }

    var isShowingSuggestions: Bool { currentEntryID.map { anchorIndex(ofSuggestions: $0) != nil } ?? false }

    private static let suggestionsPrefix = "suggestions-"

    private static func suggestionsID(after entryID: String) -> String { suggestionsPrefix + entryID }

    // Position de la vidéo qui précède le carrousel `id` ; nil si `id` n'est pas un carrousel affiché.
    private func anchorIndex(ofSuggestions id: String) -> Int? {
        guard showsSuggestions, id.hasPrefix(Self.suggestionsPrefix) else { return nil }
        let anchor = String(id.dropFirst(Self.suggestionsPrefix.count))
        guard suggestionAnchors.contains(anchor) else { return nil }
        return entries.firstIndex { $0.id == anchor }
    }

    // Suggestions à voir ou non (chargées, toutes écartées, connexion) : le carrousel apparaît ou disparaît. Affiché
    // quand il disparaît, la vidéo suivante devient courante.
    func setShowsSuggestions(_ shows: Bool) {
        guard shows != showsSuggestions else { return }
        guard !shows, let currentEntryID, let index = anchorIndex(ofSuggestions: currentEntryID) else {
            showsSuggestions = shows
            return
        }
        showsSuggestions = false
        self.currentEntryID = nil
        show(entries[min(index + 1, entries.count - 1)].id)
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
        moveSuggestionAnchors(removing: videoIDs)
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

    // Carrousel ancré à une vidéo retirée : il passe à la vidéo d'avant (rien avant : il disparaît).
    private func moveSuggestionAnchors(removing videoIDs: Set<String>) {
        let wasShowingSuggestions = isShowingSuggestions
        var anchors: [String] = []
        for anchor in suggestionAnchors {
            guard let index = entries.firstIndex(where: { $0.id == anchor }) else { continue }
            let kept = entries[...index].last { !videoIDs.contains($0.video.id) }
            if let kept, !anchors.contains(kept.id) {
                anchors.append(kept.id)
                if wasShowingSuggestions, currentEntryID == Self.suggestionsID(after: anchor) {
                    currentEntryID = Self.suggestionsID(after: kept.id)
                }
            }
        }
        suggestionAnchors = anchors
    }

    // Nouvelle session (tirer pour actualiser, connexion ou déconnexion : l'état des boutons change).
    func reload() async {
        viewTask?.cancel()
        watch.finish(.leave)
        playback.pauseAll()
        entries = []
        currentEntryID = nil
        nextCursor = nil
        videoCount = 0
        suggestionAnchors = []
        generation += 1
        reloadCount += 1
        viewTracker = ViewTracker()
        await loadFirstPage()
    }

    // La vidéo `entryID` devient la vidéo affichée (défilement).
    func show(_ entryID: String) {
        if let anchorIndex = anchorIndex(ofSuggestions: entryID) {
            showSuggestions(entryID, anchorIndex: anchorIndex)
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        currentEntryID = entryID
        isPaused = false
        let video = entries[index].video
        // Avant de changer de lecteur : la position de la vidéo quittée est lue ici (moment du swipe).
        watch.finish(.swipe)
        // Inactif (vidéo seule par-dessus, autre onglet), le feed ne touche pas aux lecteurs partagés : il retirerait
        // celui de la vidéo seule (bug rencontré : lien ouvert pendant le chargement du feed, vidéo figée). Sa fenêtre
        // est rechargée quand il redevient actif (`setActive`).
        if isActive {
            playback.keepLoaded(PreloadPolicy.window(around: index, count: entries.count).map { entries[$0].video })
        }
        if isActive && !maskedVideoIDs.contains(video.id) {
            playback.play(video.id)
            watch.play(video)
            scheduleView(of: video)
        }
        if PreloadPolicy.shouldLoadMore(currentIndex: index, count: entries.count) {
            Task { await loadMore() }
        }
    }

    // Carrousel affiché : aucune vidéo ne joue ; la suivante reste préchargée.
    private func showSuggestions(_ id: String, anchorIndex: Int) {
        currentEntryID = id
        isPaused = false
        viewTask?.cancel()
        watch.finish(.swipe)
        if isActive {
            playback.keepLoaded(PreloadPolicy.window(around: anchorIndex, count: entries.count).map { entries[$0].video })
            playback.pauseAll()
        }
        if PreloadPolicy.shouldLoadMore(currentIndex: anchorIndex, count: entries.count) {
            Task { await loadMore() }
        }
    }

    // Défilement automatique (ADR-067) : la vidéo `videoID` vient de finir ; renvoie l'entrée suivante à afficher, si la
    // vidéo finie est bien la vidéo courante, lue (ni en pause, ni masquée, onglet affiché) et qu'il y en a une après.
    func entryAfterEnd(of videoID: String) -> String? {
        guard isActive, !isPaused, let current = currentVideo, current.id == videoID, !maskedVideoIDs.contains(videoID),
            case let pages = pages, let index = pages.firstIndex(where: { $0.id == currentEntryID }), pages.indices.contains(index + 1)
        else { return nil }
        return pages[index + 1].id
    }

    // Toucher la vidéo : pause ou reprise.
    func togglePause() {
        guard let video = currentVideo, !maskedVideoIDs.contains(video.id) else { return }
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

    // Vidéos signalées (voile « Merci pour ton signalement ») : la courante s'arrête quand elle est masquée, et reprend
    // quand le voile est retiré (« Afficher la vidéo »), sauf si elle était en pause.
    func setMasked(_ ids: Set<String>) {
        let wasMasked = currentVideo.map { maskedVideoIDs.contains($0.id) } ?? false
        maskedVideoIDs = ids
        guard let video = currentVideo else { return }
        let isMasked = ids.contains(video.id)
        if isMasked && !wasMasked {
            viewTask?.cancel()
            watch.pause()
            playback.pauseAll()
        } else if !isMasked && wasMasked && isActive && !isPaused {
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
        } else if let video = currentVideo, !isPaused, !maskedVideoIDs.contains(video.id) {
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
            // La fenêtre de préchargement peut maintenant inclure la vidéo suivante (feed actif seulement, voir `show`).
            if isActive, let currentEntryID, let index = entries.firstIndex(where: { $0.id == currentEntryID }) {
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
        for video in page.videos {
            let entry = Entry(id: "\(generation)-\(video.id)", video: video)
            entries.append(entry)
            videoCount += 1
            if case .endlessFeed = mode, SuggestionCarouselRules.isSlot(afterVideo: videoCount) { suggestionAnchors.append(entry.id) }
        }
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
