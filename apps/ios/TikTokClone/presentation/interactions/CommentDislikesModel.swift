import Foundation
import Observation

// « Je n'aime pas » sur les commentaires (ADR-060, choix du développeur) : sur l'appareil seulement, le commentaire est
// replié (« Commentaire masqué · Afficher »). Un seul pour toute l'app (`AppContainer.commentDislikes`), oublié à chaque
// changement de session.
@MainActor
@Observable
final class CommentDislikesModel {
    private(set) var disliked: DislikedComments
    private let store: any DislikedCommentsStore

    init(store: any DislikedCommentsStore) {
        self.store = store
        disliked = DislikedComments(ids: store.dislikedComments)
    }

    func isDisliked(_ commentID: String) -> Bool {
        disliked.contains(commentID)
    }

    func toggle(_ commentID: String) {
        disliked.toggle(commentID)
        store.setDislikedComments(disliked.ids)
    }

    func reset() {
        disliked = DislikedComments()
        store.setDislikedComments([])
    }
}
