import Foundation
import Observation

// Lives à faire défiler (ADR-066), ouverts par l'icône « LIVE » de l'accueil : tous les lives en cours visibles, lus une
// fois à l'ouverture (comptes suivis d'abord, puis les plus regardés). Un seul est connecté à la fois : `currentID`.
@MainActor
@Observable
final class LiveFeedModel {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var lives: [LiveStream] = []
    var currentID: String?

    private let load: LoadDiscoverLivesUseCase

    init(load: LoadDiscoverLivesUseCase) {
        self.load = load
    }

    func start() async {
        state = .loading
        do {
            lives = try await load()
            currentID = lives.first?.id
            state = lives.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(AppError.from(error).message)
        }
    }

    // Live suivant (1) ou précédent (-1), pour les actions de VoiceOver (ADR-076) : faux s'il n'y en a pas.
    @discardableResult
    func move(by offset: Int) -> Bool {
        guard let currentID, let index = lives.firstIndex(where: { $0.id == currentID }), lives.indices.contains(index + offset) else { return false }
        self.currentID = lives[index + offset].id
        return true
    }

    func hasPrevious(before liveID: String) -> Bool {
        guard let index = lives.firstIndex(where: { $0.id == liveID }) else { return false }
        return index > 0
    }

    // Y a-t-il un live après celui-ci (« Balaie vers le haut pour le live suivant ») ?
    func hasNext(after liveID: String) -> Bool {
        guard let index = lives.firstIndex(where: { $0.id == liveID }) else { return false }
        return index < lives.count - 1
    }
}

// Fiche de l'auteur d'un live (ADR-066) : profil public (abonnés, abonnements, bio) et relation, relus à l'ouverture.
@MainActor
@Observable
final class LiveHostModel {
    let username: String
    private(set) var profile: UserProfile?
    private(set) var follows = false
    private(set) var failed = false

    private let loadProfile: LoadProfileUseCase
    private let loadRelationship: LoadRelationshipUseCase
    private let session: SessionStore

    init(username: String, loadProfile: LoadProfileUseCase, loadRelationship: LoadRelationshipUseCase, session: SessionStore) {
        self.username = username
        self.loadProfile = loadProfile
        self.loadRelationship = loadRelationship
        self.session = session
    }

    func load() async {
        do {
            profile = try await loadProfile(username: username)
        } catch {
            failed = true
            return
        }
        if session.isSignedIn, session.profile?.username != username {
            follows = (try? await loadRelationship(username: username))?.following ?? false
        }
    }
}
