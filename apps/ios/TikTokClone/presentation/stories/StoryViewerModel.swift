import Foundation
import Observation

// Visionneuse de stories (ADR-051) : les stories d'un compte puis celles des comptes suivants de la rangée.
// - Une story photo dure 5 s (`tick`), une story vidéo sa durée (`videoProgress`, `videoEnded`, donnés par la vue).
// - Toucher à droite : la suivante ; à gauche : la précédente ; après la dernière d'un compte, le compte suivant.
// - Appui long, réponse en cours d'écriture, feuille ouverte, app en arrière-plan : pause.
// - Chaque story d'un autre compte est marquée vue à son affichage (compte connecté) ; l'anneau suit (StoriesModel).
@MainActor
@Observable
final class StoryViewerModel {
    enum State: Equatable {
        case loading
        case showing
        case failed(String)
        // Plus rien à montrer : la vue se ferme.
        case finished
    }

    // Raisons d'être en pause ; la lecture reprend quand il n'en reste aucune.
    enum PauseReason: Hashable {
        case holding, replying, sheet, background
    }

    let authors: [UserSummary]
    let source: StorySource
    private(set) var state: State = .loading
    private(set) var position: StoryPosition
    private(set) var stories: [Story] = []
    // Avancement de la story courante, de 0 à 1.
    private(set) var progress: Double = 0
    private(set) var pauses: Set<PauseReason> = []
    // Message d'une action (réponse envoyée, erreur), affiché brièvement.
    var notice: String?
    private var loaded: [Int: [Story]] = [:]
    private var likeInFlight: Set<String> = []

    private let loadStories: LoadUserStoriesUseCase
    private let recordView: RecordStoryViewUseCase
    private let setLiked: SetStoryLikedUseCase
    private let deleteStory: DeleteStoryUseCase
    private let reply: ReplyToStoryUseCase
    private let model: StoriesModel
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(
        authors: [UserSummary],
        startAuthor: Int = 0,
        source: StorySource,
        loadStories: LoadUserStoriesUseCase,
        recordView: RecordStoryViewUseCase,
        setLiked: SetStoryLikedUseCase,
        deleteStory: DeleteStoryUseCase,
        reply: ReplyToStoryUseCase,
        model: StoriesModel,
        session: SessionStore,
        analytics: AnalyticsModel
    ) {
        self.authors = authors
        self.source = source
        self.position = StoryPosition(author: min(max(0, startAuthor), max(0, authors.count - 1)), story: 0)
        self.loadStories = loadStories
        self.recordView = recordView
        self.setLiked = setLiked
        self.deleteStory = deleteStory
        self.reply = reply
        self.model = model
        self.session = session
        self.analytics = analytics
    }

    var current: Story? {
        stories.indices.contains(position.story) ? stories[position.story] : nil
    }

    var isPaused: Bool { !pauses.isEmpty }

    var isOwn: Bool {
        guard let current else { return false }
        return current.author.id == session.profile?.id
    }

    // Premier affichage : stories du premier compte, à partir de la première pas encore vue.
    func start() async {
        guard state == .loading, !authors.isEmpty else {
            if authors.isEmpty { state = .finished }
            return
        }
        await showAuthor(position.author)
    }

    // Après un échec de chargement : on relit le compte courant.
    func retry() async {
        guard case .failed = state else { return }
        state = .loading
        await showAuthor(position.author)
    }

    // ─── Lecture ─────────────────────────────────────────────────────────────

    // Horloge des photos (la vue l'appelle à intervalle régulier) : 5 s par photo, puis la suivante.
    func tick(_ elapsed: Duration) {
        guard state == .showing, !isPaused, let current, current.mediaType == .photo else { return }
        progress = min(1, progress + elapsed / StoryRules.photoDuration)
        if progress >= 1 { next() }
    }

    // Lecture d'une vidéo, d'après le lecteur.
    func videoProgress(_ fraction: Double) {
        guard state == .showing, current?.mediaType == .video else { return }
        progress = min(1, max(progress, fraction))
    }

    func videoEnded() {
        guard state == .showing, current?.mediaType == .video else { return }
        next()
    }

    func next() {
        navigate(StoryNavigation.next(from: position, storiesCount: stories.count, authorsCount: authors.count))
    }

    func previous() {
        navigate(StoryNavigation.previous(from: position))
    }

    func pause(_ reason: PauseReason) {
        pauses.insert(reason)
    }

    func resume(_ reason: PauseReason) {
        pauses.remove(reason)
    }

    func close() {
        state = .finished
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    // Like optimiste ; revient en arrière en cas d'erreur. En invité : connexion.
    func toggleLike() {
        guard let story = current, !isOwn else { return }
        guard session.profile != nil else { return session.requestSignIn() }
        guard !likeInFlight.contains(story.id) else { return }
        let liked = !story.liked
        setStory(story.id) {
            $0.liked = liked
            $0.viewed = true
        }
        likeInFlight.insert(story.id)
        if liked { analytics.track(.storyLiked(story)) }
        Task {
            defer { likeInFlight.remove(story.id) }
            do {
                try await setLiked(storyID: story.id, liked: liked)
            } catch {
                setStory(story.id) { $0.liked = !liked }
                handle(error)
            }
        }
    }

    // Réponse par message à l'auteur. Renvoie vrai si elle est partie (le champ se vide). En invité : connexion.
    func sendReply(_ text: String) async -> Bool {
        guard let story = current, !isOwn else { return false }
        guard session.profile != nil else {
            session.requestSignIn()
            return false
        }
        do {
            _ = try await reply(story, text: text)
            analytics.track(.storyReplySent(story))
            notice = "Message envoyé à @\(story.author.username)"
            return true
        } catch {
            handle(error)
            return false
        }
    }

    // Sa propre story : supprimée pour de bon ; la visionneuse passe à la suivante (ou se ferme).
    func deleteCurrent() async {
        guard let story = current, isOwn else { return }
        do {
            try await deleteStory(id: story.id)
            stories.remove(at: position.story)
            loaded[position.author] = stories
            model.update(story.author.id, stories: stories)
            if stories.isEmpty {
                navigate(StoryNavigation.next(from: StoryPosition(author: position.author, story: 0), storiesCount: 0, authorsCount: authors.count))
            } else {
                show(StoryPosition(author: position.author, story: min(position.story, stories.count - 1)))
            }
        } catch {
            handle(error)
        }
    }

    // ─── Navigation ──────────────────────────────────────────────────────────

    private func navigate(_ navigation: StoryNavigation) {
        switch navigation {
        case .story(let index): show(StoryPosition(author: position.author, story: index))
        case .author(let index): Task { await showAuthor(index) }
        case .close: state = .finished
        }
    }

    // Compte de la rangée : ses stories (relues une fois), à partir de la première pas encore vue. Un compte qui n'en a
    // plus (expirées, supprimées) est sauté.
    private func showAuthor(_ index: Int) async {
        var index = index
        while authors.indices.contains(index) {
            let author = authors[index]
            if loaded[index] == nil {
                state = .loading
                do {
                    let stories = try await loadStories(username: author.username)
                    loaded[index] = stories
                    model.update(author.id, stories: stories)
                } catch {
                    let error = AppError.from(error)
                    // Compte supprimé entre-temps : on passe au suivant.
                    if error != .notFound {
                        state = .failed(error.message)
                        return
                    }
                    loaded[index] = []
                }
            }
            let stories = loaded[index] ?? []
            if !stories.isEmpty {
                position = StoryPosition(author: index, story: StoryRules.startIndex(of: stories))
                self.stories = stories
                show(position)
                return
            }
            index += 1
        }
        state = .finished
    }

    private func show(_ position: StoryPosition) {
        self.position = position
        progress = 0
        state = .showing
        guard let story = current else { return }
        analytics.track(.storyViewed(story, source: source))
        markViewed(story)
    }

    // Vue enregistrée à l'affichage d'une story d'un autre compte, pour un compte connecté (au mieux).
    private func markViewed(_ story: Story) {
        guard !isOwn, session.profile != nil, !story.viewed else { return }
        setStory(story.id) { $0.viewed = true }
        model.update(story.author.id, stories: stories)
        Task { try? await recordView(storyID: story.id) }
    }

    private func setStory(_ id: String, _ change: (inout Story) -> Void) {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        change(&stories[index])
        loaded[position.author] = stories
    }

    private func handle(_ error: any Error) {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return
        }
        notice = error.message
    }
}
