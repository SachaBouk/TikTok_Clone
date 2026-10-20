import Foundation
import Observation

// Brouillons du compte connecté (ADR-065), sur l'iPhone : grille « Brouillons » de son profil, enregistrement depuis la
// création, réouverture. Un seul pour toute l'app (`AppContainer.drafts`) ; tous oubliés à chaque changement de session.
@MainActor
@Observable
final class DraftsModel {
    private(set) var drafts: [VideoDraft] = []

    private let store: any DraftStore
    private let session: SessionStore

    init(store: any DraftStore, session: SessionStore) {
        self.store = store
        self.session = session
    }

    var count: Int { drafts.count }

    func reload() {
        drafts = session.profile.map { store.all(userID: $0.id) } ?? []
    }

    // Enregistre le brouillon (ses fichiers y sont déplacés) ; nil sans compte connecté.
    @discardableResult
    func save(_ draft: VideoDraft, thumbnail: Data?) throws -> VideoDraft {
        let saved = try store.save(draft, thumbnail: thumbnail)
        drafts.removeAll { $0.id == saved.id }
        drafts.insert(saved, at: 0)
        return saved
    }

    // Ouvre un brouillon : il quitte la liste, ses fichiers retournent dans le dossier temporaire.
    func open(_ draft: VideoDraft) throws -> VideoDraft {
        let opened = try store.open(draft)
        drafts.removeAll { $0.id == draft.id }
        return opened
    }

    func delete(_ draft: VideoDraft) {
        store.delete(draft)
        drafts.removeAll { $0.id == draft.id }
    }

    func thumbnailURL(of draft: VideoDraft) -> URL? {
        store.thumbnailURL(of: draft)
    }

    // Changement de session : les brouillons (et leurs fichiers) sont supprimés.
    func reset() {
        store.deleteAll()
        drafts = []
    }
}
