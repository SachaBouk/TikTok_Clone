import Foundation
import Observation

// Feuille de commentaires d'une vidéo, façon TikTok (ADR-060) : lisible par tous, écrire demande un compte (ADR-010).
// - Commentaires du plus récent au plus ancien ; sous chacun, son fil de réponses (un seul niveau), replié tant qu'on
//   ne touche pas « Afficher N réponses », lu page par page du plus ancien au plus récent.
// - J'aime optimiste, comme les réactions d'une vidéo ; « Je n'aime pas » sur l'appareil seulement (`CommentDislikesModel`).
// - Répondre : bandeau « Réponse à @pseudo » ; une réponse à une réponse commence par « @pseudo » et va dans le même fil.
// - « @ » : suggestions de comptes pour la mention en cours de saisie (abonnements, puis recherche).
@MainActor
@Observable
final class CommentsViewModel {
    // Lignes de la liste : commentaires, réponses dépliées, et sous chaque fil la ligne « Afficher N réponses / Masquer ».
    enum Row: Identifiable, Equatable {
        case comment(VideoComment)
        case reply(VideoComment)
        case thread(parent: VideoComment, remaining: Int, isExpanded: Bool, isLoading: Bool)

        var id: String {
            switch self {
            case .comment(let comment), .reply(let comment): comment.id
            case .thread(let parent, _, _, _): "thread-\(parent.id)"
            }
        }
    }

    let video: FeedVideo
    private(set) var comments: [VideoComment] = []
    // Réponses chargées, par commentaire d'origine (de la plus ancienne à la plus récente).
    private(set) var replies: [String: [VideoComment]] = [:]
    private(set) var expandedThreads: Set<String> = []
    private(set) var loadingThreads: Set<String> = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var count: Int
    private(set) var isSending = false
    var draft = ""
    var errorMessage: String?
    // Commentaire ou réponse auquel on répond.
    private(set) var replyingTo: VideoComment?
    private(set) var mentionSuggestions: [UserSummary] = []

    private let loadComments: LoadCommentsUseCase
    private let loadReplies: LoadRepliesUseCase
    private let addComment: AddCommentUseCase
    private let deleteComment: DeleteCommentUseCase
    private let setCommentLike: SetCommentLikeUseCase
    private let mentionSuggestionsFor: MentionSuggestionsUseCase
    private let dislikes: CommentDislikesModel
    private let session: SessionStore
    private let analytics: AnalyticsModel
    // Prévient les autres écrans du changement du nombre de commentaires (+1, -1, ou plus pour un fil supprimé).
    private let onCountChange: (Int) -> Void
    private var nextCursor: String?
    private var hasLoaded = false
    // Fils dont la page suivante de réponses reste à lire ; un fil lu jusqu'au bout n'y est plus.
    private var replyCursors: [String: String] = [:]
    private var exhaustedThreads: Set<String> = []
    private var pendingLikes: Set<String> = []

    init(
        video: FeedVideo,
        loadComments: LoadCommentsUseCase,
        loadReplies: LoadRepliesUseCase,
        addComment: AddCommentUseCase,
        deleteComment: DeleteCommentUseCase,
        setCommentLike: SetCommentLikeUseCase,
        mentionSuggestions: MentionSuggestionsUseCase,
        dislikes: CommentDislikesModel,
        session: SessionStore,
        analytics: AnalyticsModel,
        onCountChange: @escaping (Int) -> Void
    ) {
        self.video = video
        self.count = video.stats.comments
        self.loadComments = loadComments
        self.loadReplies = loadReplies
        self.addComment = addComment
        self.deleteComment = deleteComment
        self.setCommentLike = setCommentLike
        self.mentionSuggestionsFor = mentionSuggestions
        self.dislikes = dislikes
        self.session = session
        self.analytics = analytics
        self.onCountChange = onCountChange
    }

    var isSignedIn: Bool { session.isSignedIn }
    var hasMore: Bool { nextCursor != nil }
    var canSend: Bool { CommentRules.sanitized(draft) != nil && !isSending }
    var ownProfile: UserProfile? { session.profile }

    // Lignes affichées, dans l'ordre.
    var rows: [Row] {
        comments.flatMap { comment -> [Row] in
            var rows: [Row] = [.comment(comment)]
            let loaded = replies[comment.id] ?? []
            let isLoading = loadingThreads.contains(comment.id)
            if expandedThreads.contains(comment.id) {
                // Déplié : les réponses lues, puis « Afficher N de plus » s'il en reste, et « Masquer ».
                rows += loaded.map(Row.reply)
                let remaining = exhaustedThreads.contains(comment.id) ? 0 : max(0, comment.repliesCount - loaded.count)
                rows.append(.thread(parent: comment, remaining: remaining, isExpanded: true, isLoading: isLoading))
            } else if comment.repliesCount > 0 || !loaded.isEmpty {
                // Replié : « Afficher N réponses ».
                rows.append(.thread(parent: comment, remaining: max(comment.repliesCount, loaded.count), isExpanded: false, isLoading: isLoading))
            }
            return rows
        }
    }

    func isOwn(_ comment: VideoComment) -> Bool {
        session.profile?.id == comment.author.id
    }

    // Sa propre vidéo : on peut y supprimer les commentaires des autres (ADR-042), en silence.
    var isOwnVideo: Bool {
        session.profile?.id == video.author.id
    }

    // Badge « Créateur » : commentaire de l'auteur de la vidéo.
    func isCreator(_ comment: VideoComment) -> Bool {
        comment.author.id == video.author.id
    }

    func canDelete(_ comment: VideoComment) -> Bool {
        isOwn(comment) || isOwnVideo
    }

    func isDisliked(_ comment: VideoComment) -> Bool {
        dislikes.isDisliked(comment.id)
    }

    // « Je n'aime pas » : replie le commentaire chez soi (ou le rouvre).
    func toggleDislike(_ comment: VideoComment) {
        dislikes.toggle(comment.id)
    }

    func start() async {
        guard !hasLoaded else { return }
        await load(cursor: nil)
    }

    func loadMore() async {
        guard let nextCursor, !isLoading else { return }
        await load(cursor: nextCursor)
    }

    // « Afficher N réponses » : déplie le fil (déjà lu : sans relire), ou lit la page suivante s'il en reste.
    func showReplies(of parent: VideoComment) async {
        let wasExpanded = expandedThreads.contains(parent.id)
        expandedThreads.insert(parent.id)
        if !wasExpanded && !(replies[parent.id] ?? []).isEmpty { return }
        guard !exhaustedThreads.contains(parent.id), loadingThreads.insert(parent.id).inserted else { return }
        defer { loadingThreads.remove(parent.id) }
        do {
            let page = try await EmptyPages.fetch(
                replyCursors[parent.id], load: { try await loadReplies(commentID: parent.id, cursor: $0) },
                isEmpty: { $0.comments.isEmpty }, next: { $0.nextCursor })
            let known = Set((replies[parent.id] ?? []).map(\.id))
            replies[parent.id, default: []] += page.comments.filter { !known.contains($0.id) }
            if let cursor = page.nextCursor {
                replyCursors[parent.id] = cursor
            } else {
                replyCursors[parent.id] = nil
                exhaustedThreads.insert(parent.id)
            }
        } catch {
            report(error)
        }
    }

    // « Masquer » : replie le fil (les réponses lues restent en mémoire).
    func hideReplies(of parent: VideoComment) {
        expandedThreads.remove(parent.id)
    }

    // « Répondre » : bandeau « Réponse à @pseudo », et « @pseudo » au début du texte pour une réponse à une réponse.
    func reply(to comment: VideoComment) {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        replyingTo = comment
        let prefix = CommentRules.replyPrefix(to: comment)
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.hasPrefix("@") { draft = prefix }
    }

    func cancelReply() {
        if let replyingTo, draft == CommentRules.replyPrefix(to: replyingTo) { draft = "" }
        replyingTo = nil
    }

    func addEmoji(_ emoji: String) {
        draft += emoji
    }

    // Bouton « @ » : commence une mention à la fin du texte.
    func startMention() {
        draft = MentionRules.startingMention(in: draft)
    }

    // Suggestions pour la mention en cours de saisie (appelé par la vue, 250 ms après la frappe).
    func updateMentionSuggestions() async {
        guard session.isSignedIn, let prefix = MentionRules.typedPrefix(in: draft) else {
            mentionSuggestions = []
            return
        }
        let suggestions = (try? await mentionSuggestionsFor(prefix: prefix, username: session.profile?.username)) ?? []
        // La saisie a pu changer pendant la requête.
        guard MentionRules.typedPrefix(in: draft) == prefix else { return }
        mentionSuggestions = suggestions.filter { $0.id != session.profile?.id }
    }

    func chooseMention(_ user: UserSummary) {
        draft = MentionRules.completing(draft, with: user.username)
        mentionSuggestions = []
    }

    func send() async {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            let comment = try await addComment(videoID: video.id, text: draft, replyTo: replyingTo)
            if let parentID = comment.parentID {
                replies[parentID, default: []].append(comment)
                expandedThreads.insert(parentID)
                update(parentID) { $0.repliesCount += 1 }
            } else {
                comments.insert(comment, at: 0)
            }
            draft = ""
            replyingTo = nil
            mentionSuggestions = []
            count += 1
            onCountChange(1)
            analytics.track(.commentPosted(videoID: video.id))
        } catch {
            report(error)
        }
    }

    // J'aime d'un commentaire ou d'une réponse : optimiste, puis le compteur renvoyé par l'API ; en cas d'erreur, l'état
    // d'avant revient. Sur sa propre vidéo, « aimé par l'auteur » suit aussitôt.
    func toggleLike(_ comment: VideoComment) async {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        guard let before = find(comment.id), pendingLikes.insert(comment.id).inserted else { return }
        defer { pendingLikes.remove(comment.id) }
        let liked = !(before.viewerLiked ?? false)
        update(comment.id) {
            $0.viewerLiked = liked
            $0.likesCount = max(0, $0.likesCount + (liked ? 1 : -1))
            if self.isOwnVideo { $0.likedByAuthor = liked }
        }
        do {
            let state = try await setCommentLike(commentID: comment.id, active: liked)
            update(comment.id) {
                $0.viewerLiked = state.active
                $0.likesCount = state.count
            }
        } catch {
            update(comment.id) { $0 = before }
            report(error)
        }
    }

    // Compte bloqué depuis la feuille (profil ouvert depuis un commentaire) : ses commentaires et réponses disparaissent,
    // comme au prochain chargement. Le nombre affiché ne change pas : l'API les compte toujours.
    func removeComments(byAuthors ids: Set<String>) {
        comments.removeAll { ids.contains($0.author.id) }
        for key in replies.keys { replies[key]?.removeAll { ids.contains($0.author.id) } }
    }

    // Suppression de son commentaire, ou de celui d'un autre sur sa vidéo (ADR-042) ; un commentaire emporte ses réponses.
    // Il revient à sa place si l'API refuse.
    func delete(_ comment: VideoComment) async {
        guard canDelete(comment) else { return }
        if replyingTo?.id == comment.id || replyingTo?.parentID == comment.id { cancelReply() }
        if let parentID = comment.parentID {
            guard let index = replies[parentID]?.firstIndex(where: { $0.id == comment.id }) else { return }
            replies[parentID]?.remove(at: index)
            update(parentID) { $0.repliesCount = max(0, $0.repliesCount - 1) }
            changeCount(by: -1)
            do {
                try await deleteComment(id: comment.id)
            } catch {
                replies[parentID]?.insert(comment, at: min(index, replies[parentID]?.count ?? 0))
                update(parentID) { $0.repliesCount += 1 }
                changeCount(by: 1)
                report(error)
            }
            return
        }
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let removed = comments.remove(at: index)
        let removedCount = 1 + removed.repliesCount
        changeCount(by: -removedCount)
        do {
            try await deleteComment(id: comment.id)
            replies[comment.id] = nil
        } catch {
            comments.insert(removed, at: min(index, comments.count))
            changeCount(by: removedCount)
            report(error)
        }
    }

    private func changeCount(by delta: Int) {
        count = max(0, count + delta)
        onCountChange(delta)
    }

    private func find(_ id: String) -> VideoComment? {
        comments.first { $0.id == id } ?? replies.values.lazy.compactMap { $0.first { $0.id == id } }.first
    }

    // Change un commentaire ou une réponse, où qu'il soit.
    private func update(_ id: String, _ change: (inout VideoComment) -> Void) {
        if let index = comments.firstIndex(where: { $0.id == id }) {
            change(&comments[index])
            return
        }
        for key in replies.keys {
            if let index = replies[key]?.firstIndex(where: { $0.id == id }) {
                change(&replies[key]![index])
                return
            }
        }
    }

    private func load(cursor: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await EmptyPages.fetch(
                cursor, load: { try await loadComments(videoID: video.id, cursor: $0) },
                isEmpty: { $0.comments.isEmpty }, next: { $0.nextCursor })
            comments += page.comments.filter { new in !comments.contains { $0.id == new.id } }
            nextCursor = page.nextCursor
            hasLoaded = true
            loadError = nil
        } catch {
            if cursor == nil { loadError = AppError.from(error).message }
        }
    }

    private func report(_ error: any Error) {
        let error = AppError.from(error)
        if error == .sessionExpired { session.sessionExpired() }
        errorMessage = error.message
    }
}
