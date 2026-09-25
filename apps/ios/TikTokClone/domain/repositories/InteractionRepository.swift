// Port des interactions sociales (ADR-016). Réactions et follow sont idempotents côté API :
// renvoyer le même état ne change rien, et la réponse porte le compteur à jour.
protocol InteractionRepository: Sendable {
    func setReaction(_ kind: ReactionKind, videoID: String, active: Bool) async throws -> InteractionState
    // `count` : abonnés du compte.
    func setFollow(username: String, active: Bool) async throws -> InteractionState
    // Nouveau nombre de partages.
    func recordShare(videoID: String) async throws -> Int
    func comments(videoID: String, cursor: String?) async throws -> CommentPage
    func addComment(videoID: String, content: String) async throws -> VideoComment
    func deleteComment(id: String) async throws
}
