// Port des interactions sociales (ADR-016). Réactions et follow sont idempotents côté API :
// renvoyer le même état ne change rien, et la réponse porte le compteur à jour.
protocol InteractionRepository: Sendable {
    func setReaction(_ kind: ReactionKind, videoID: String, active: Bool) async throws -> InteractionState
    // `count` : abonnés du compte.
    func setFollow(username: String, active: Bool) async throws -> InteractionState
    // Nouveau nombre de partages.
    func recordShare(videoID: String) async throws -> Int
    // Commentaires d'origine (ADR-060) ; les réponses d'un fil se lisent par `replies`.
    func comments(videoID: String, cursor: String?) async throws -> CommentPage
    func replies(commentID: String, cursor: String?) async throws -> CommentPage
    // `replyToID` : commentaire ou réponse auquel on répond.
    func addComment(videoID: String, content: String, replyToID: String?) async throws -> VideoComment
    // J'aime d'un commentaire ; `count` : j'aime du commentaire.
    func setCommentLike(commentID: String, active: Bool) async throws -> InteractionState
    func deleteComment(id: String) async throws
    // Historique des commentaires du compte connecté (privé), du plus récent au plus ancien.
    func myComments(cursor: String?) async throws -> CommentHistoryPage
}

// « Je n'aime pas » sur les commentaires (ADR-060), sur l'appareil seulement.
protocol DislikedCommentsStore: Sendable {
    var dislikedComments: [String] { get }
    func setDislikedComments(_ ids: [String])
}
