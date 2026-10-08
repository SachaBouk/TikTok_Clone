import Foundation
import Observation

// Stories (ADR-051), un seul modèle pour toute l'app (AppContainer) : rangée de la boîte de réception et anneaux autour des
// avatars (rangée, feed, profils). Ce que la visionneuse a montré ici est superposé à ce que l'API a renvoyé : un compte
// dont on vient de voir toutes les stories passe en gris partout.
@MainActor
@Observable
final class StoriesModel {
    private(set) var tray: [StoryTrayEntry] = []
    private(set) var trayState: PagedListState = .idle
    // Anneaux connus, par compte (rangée, profils ouverts, visionneuse).
    private var rings: [String: StoryRing] = [:]
    // Comptes sans story visible d'après leur profil (l'anneau du feed peut être plus ancien).
    private var withoutStories: Set<String> = []

    private let loadTray: LoadStoryTrayUseCase
    private let loadStories: LoadUserStoriesUseCase
    private let session: SessionStore

    init(loadTray: LoadStoryTrayUseCase, loadStories: LoadUserStoriesUseCase, session: SessionStore) {
        self.loadTray = loadTray
        self.loadStories = loadStories
        self.session = session
    }

    // Sa propre entrée (« Ta story »), et celles de ses abonnements.
    var ownEntry: StoryTrayEntry? {
        tray.first { $0.user.id == session.profile?.id }
    }

    var followedEntries: [StoryTrayEntry] {
        tray.filter { $0.user.id != session.profile?.id }
    }

    // Rangée : à chaque (re)connexion du temps réel, à l'ouverture de la boîte de réception, après une publication.
    func refresh() async {
        guard session.profile != nil else { return }
        if tray.isEmpty { trayState = .loading }
        do {
            let entries = try await loadTray()
            tray = entries
            for entry in entries {
                rings[entry.user.id] = StoryRing(hasUnseen: entry.hasUnseen)
                withoutStories.remove(entry.user.id)
            }
            trayState = .loaded
        } catch {
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() }
            trayState = .failed(error.message)
        }
    }

    // Anneau d'un compte : ce qui est connu ici, sinon `fallback` (anneau du feed). Nil : pas de story.
    func ring(for userID: String, fallback: StoryRing? = nil) -> StoryRing? {
        if withoutStories.contains(userID) { return nil }
        return rings[userID] ?? fallback
    }

    // Profil ouvert : ses stories sont relues pour l'anneau de sa photo. Un échec ne change rien.
    func loadRing(for user: UserSummary) async {
        guard let stories = try? await loadStories(username: user.username) else { return }
        update(user.id, stories: stories)
    }

    // Stories lues par la visionneuse : l'anneau suit (gris quand tout a été vu, ou sa propre story).
    func update(_ userID: String, stories: [Story]) {
        if stories.isEmpty {
            withoutStories.insert(userID)
            rings[userID] = nil
            tray.removeAll { $0.user.id == userID }
            return
        }
        withoutStories.remove(userID)
        let isOwn = userID == session.profile?.id
        let ring = StoryRing(hasUnseen: !isOwn && stories.contains { !$0.viewed })
        rings[userID] = ring
        if let index = tray.firstIndex(where: { $0.user.id == userID }) { tray[index].hasUnseen = ring == .unseen }
    }

    func reset() {
        tray = []
        trayState = .idle
        rings = [:]
        withoutStories = []
    }
}
