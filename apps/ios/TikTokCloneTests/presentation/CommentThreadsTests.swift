import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

// Commentaires façon TikTok (ADR-060) : fils de réponses, j'aime, mentions, « Je n'aime pas ».
@MainActor
@Suite("Commentaires : réponses, j'aime, mentions")
struct CommentThreadsTests {
    let repository = FakeInteractionRepository()
    let relationships = FakeRelationshipRepository()
    let search = FakeSearchRepository()
    let dislikedStore = InMemoryDislikedCommentsStore()
    // Vidéo de bob, vue par alice (connectée).
    let video = FeedVideo.sample("v1", viewer: .empty)

    func makeViewModel(video: FeedVideo? = nil, signedIn: Bool = true, onCountChange: @escaping (Int) -> Void = { _ in }) async
        -> CommentsViewModel
    {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        return CommentsViewModel(
            video: video ?? self.video,
            loadComments: LoadCommentsUseCase(interactions: repository),
            loadReplies: LoadRepliesUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository),
            setCommentLike: SetCommentLikeUseCase(interactions: repository),
            mentionSuggestions: MentionSuggestionsUseCase(relationships: relationships, search: search),
            dislikes: CommentDislikesModel(store: dislikedStore),
            session: session,
            analytics: makeAnalytics(),
            onCountChange: onCountChange
        )
    }

    // c1 a trois réponses (r1, r2, r3) ; c2 aucune.
    func seedThread() {
        repository.state.withLock {
            $0.comments["v1"] = [.sample("c1", repliesCount: 3), .sample("c2")]
            $0.replies["c1"] = [.sample("r1", parentID: "c1"), .sample("r2", parentID: "c1", author: .alice), .sample("r3", parentID: "c1")]
        }
    }

    @Test("fil replié : « Afficher 3 réponses », puis pages du plus ancien au plus récent, « Masquer » et redéplié sans relire")
    func threads() async {
        seedThread()
        let viewModel = await makeViewModel()
        await viewModel.start()
        #expect(viewModel.rows.map(\.id) == ["c1", "thread-c1", "c2"])
        #expect(viewModel.rows[1] == .thread(parent: viewModel.comments[0], remaining: 3, isExpanded: false, isLoading: false))

        await viewModel.showReplies(of: viewModel.comments[0])
        #expect(viewModel.rows.map(\.id) == ["c1", "r1", "r2", "thread-c1", "c2"])
        #expect(viewModel.rows[3] == .thread(parent: viewModel.comments[0], remaining: 1, isExpanded: true, isLoading: false))
        await viewModel.showReplies(of: viewModel.comments[0])
        #expect(viewModel.rows.map(\.id) == ["c1", "r1", "r2", "r3", "thread-c1", "c2"])
        #expect(viewModel.rows[4] == .thread(parent: viewModel.comments[0], remaining: 0, isExpanded: true, isLoading: false))

        viewModel.hideReplies(of: viewModel.comments[0])
        #expect(viewModel.rows.map(\.id) == ["c1", "thread-c1", "c2"])
        await viewModel.showReplies(of: viewModel.comments[0])
        #expect(viewModel.rows.map(\.id) == ["c1", "r1", "r2", "r3", "thread-c1", "c2"])
        #expect(repository.calls == ["replies-c1-", "replies-c1-r2"])
    }

    @Test("répondre : bandeau, « @pseudo » pour une réponse à une réponse, réponse rangée sous le commentaire d'origine")
    func reply() async {
        seedThread()
        var deltas: [Int] = []
        let viewModel = await makeViewModel { deltas.append($0) }
        await viewModel.start()
        await viewModel.showReplies(of: viewModel.comments[0])

        let r1 = VideoComment.sample("r1", parentID: "c1")
        viewModel.reply(to: r1)
        #expect(viewModel.replyingTo == r1)
        #expect(viewModel.draft == "@bob ")
        viewModel.draft += "merci"
        await viewModel.send()
        #expect(repository.calls.last == "comment-v1-@bob merci-reply-r1")
        #expect(viewModel.replyingTo == nil)
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.comments[0].repliesCount == 4)
        #expect(viewModel.replies["c1"]?.last?.content == "@bob merci")
        #expect(viewModel.count == 4)
        #expect(deltas == [1])

        // Annuler une réponse retire le « @pseudo » ajouté.
        viewModel.reply(to: r1)
        viewModel.cancelReply()
        #expect(viewModel.draft.isEmpty)
        // Réponse au commentaire d'origine : pas de « @pseudo ».
        viewModel.reply(to: viewModel.comments[0])
        #expect(viewModel.draft.isEmpty)
    }

    @Test("répondre en invité : la connexion s'ouvre")
    func replyAsGuest() async {
        seedThread()
        let viewModel = await makeViewModel(signedIn: false)
        await viewModel.start()
        viewModel.reply(to: viewModel.comments[0])
        #expect(viewModel.replyingTo == nil)
    }

    @Test("j'aime optimiste puis compteur de l'API ; sur sa vidéo, « aimé par l'auteur » ; échec : état d'avant")
    func like() async throws {
        repository.state.withLock { $0.comments["v1"] = [.sample("c1")] }
        repository.setServerCount(4, for: "comment-c1")
        let viewModel = await makeViewModel()
        await viewModel.start()
        await viewModel.toggleLike(viewModel.comments[0])
        #expect(viewModel.comments[0].viewerLiked == true)
        #expect(viewModel.comments[0].likesCount == 5)
        #expect(!viewModel.comments[0].likedByAuthor)
        await viewModel.toggleLike(viewModel.comments[0])
        #expect(viewModel.comments[0].viewerLiked == false)
        #expect(viewModel.comments[0].likesCount == 4)

        repository.fail(with: .blocked)
        await viewModel.toggleLike(viewModel.comments[0])
        #expect(viewModel.comments[0].viewerLiked == false)
        #expect(viewModel.comments[0].likesCount == 4)
        #expect(viewModel.errorMessage == AppError.blocked.message)

        // Vidéo d'alice : son j'aime est celui de l'auteur.
        repository.fail(with: nil)
        let mine = FeedVideo.sample("v1", author: "alice")
        let own = await makeViewModel(
            video: FeedVideo(
                id: mine.id, description: mine.description, hlsURL: mine.hlsURL, thumbnailURL: mine.thumbnailURL, createdAt: mine.createdAt,
                stats: mine.stats, author: .alice, viewer: mine.viewer))
        await own.start()
        await own.toggleLike(own.comments[0])
        #expect(own.comments[0].likedByAuthor)
        #expect(own.isCreator(VideoComment.sample("x", author: .alice)))
    }

    @Test("supprimer un commentaire retire ses réponses du compte ; une réponse : -1 au fil")
    func deleteThread() async {
        seedThread()
        repository.state.withLock { $0.comments["v1"] = [.sample("c1", author: .alice, repliesCount: 3)] }
        var deltas: [Int] = []
        let viewModel = await makeViewModel { deltas.append($0) }
        await viewModel.start()
        await viewModel.showReplies(of: viewModel.comments[0])
        await viewModel.delete(viewModel.replies["c1"]![1])
        #expect(viewModel.replies["c1"]?.map(\.id) == ["r1"])
        #expect(viewModel.comments[0].repliesCount == 2)
        await viewModel.delete(viewModel.comments[0])
        #expect(viewModel.comments.isEmpty)
        #expect(deltas == [-1, -3])
    }

    @Test("mentions : « @ » commence une mention, suggestions (abonnements, puis recherche), choix qui complète le texte")
    func mentions() async {
        relationships.state.withLock {
            $0.follows[.following] = [FollowEntry(user: .bob, followedAt: .now, viewer: nil)]
        }
        let ines = UserSummary(id: "ines-id", username: "ines.m", displayName: "Inès", avatarURL: nil)
        search.state.withLock {
            $0.accounts["in"] = [AccountSearchPage(results: [AccountSearchResult(user: ines, followersCount: 1, viewer: nil)], nextCursor: nil)]
        }
        let viewModel = await makeViewModel()
        viewModel.draft = "Regarde"
        viewModel.startMention()
        #expect(viewModel.draft == "Regarde @")
        await viewModel.updateMentionSuggestions()
        #expect(viewModel.mentionSuggestions == [.bob])

        viewModel.draft = "Regarde @in"
        await viewModel.updateMentionSuggestions()
        #expect(viewModel.mentionSuggestions == [ines])
        viewModel.chooseMention(ines)
        #expect(viewModel.draft == "Regarde @ines.m ")
        #expect(viewModel.mentionSuggestions.isEmpty)
        await viewModel.updateMentionSuggestions()
        #expect(viewModel.mentionSuggestions.isEmpty)
    }

    @Test("« Je n'aime pas » : replié sur l'appareil, gardé, rouvert ; emojis ajoutés au texte")
    func dislikeAndEmojis() async {
        repository.state.withLock { $0.comments["v1"] = [.sample("c1")] }
        let viewModel = await makeViewModel()
        await viewModel.start()
        viewModel.toggleDislike(viewModel.comments[0])
        #expect(viewModel.isDisliked(viewModel.comments[0]))
        #expect(dislikedStore.dislikedComments == ["c1"])
        #expect(CommentDislikesModel(store: dislikedStore).isDisliked("c1"))
        viewModel.toggleDislike(viewModel.comments[0])
        #expect(!viewModel.isDisliked(viewModel.comments[0]))

        viewModel.addEmoji("😂")
        #expect(viewModel.draft == "😂")
        #expect(CommentRules.quickEmojis.count == 7)
    }

    @Test("règles des mentions : occurrences, point final, email ignoré, saisie en cours")
    func mentionRules() {
        let text = "Merci @Ines.M et @nathan_p. Écris à lea@demo.local"
        #expect(MentionRules.occurrences(in: text).map(\.username) == ["ines.m", "nathan_p"])
        let second = MentionRules.occurrences(in: text)[1]
        #expect(text[second.range] == "@nathan_p")
        #expect(MentionRules.typedPrefix(in: "Salut @Na") == "na")
        #expect(MentionRules.typedPrefix(in: "Salut @") == "")
        #expect(MentionRules.typedPrefix(in: "lea@de") == nil)
        #expect(MentionRules.typedPrefix(in: "Salut @nathan ") == nil)
        #expect(MentionRules.completing("Salut @na", with: "nathan.petit") == "Salut @nathan.petit ")
        #expect(MentionRules.startingMention(in: "") == "@")
        #expect(MentionRules.startingMention(in: "Salut ") == "Salut @")
    }

    @Test("date courte : relative la première semaine, puis jour et mois, et l'année si elle diffère")
    func dateStyle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(CommentRules.dateStyle(for: now.addingTimeInterval(-3600), now: now) == .relative)
        #expect(CommentRules.dateStyle(for: now.addingTimeInterval(-8 * 24 * 3600), now: now) == .dayMonth)
        #expect(CommentRules.dateStyle(for: now.addingTimeInterval(-400 * 24 * 3600), now: now) == .full)
    }

    @Test("« Je n'aime pas » : 500 retenus au plus, les plus anciens oubliés")
    func dislikedLimit() {
        var disliked = DislikedComments(ids: (0..<500).map(String.init))
        disliked.toggle("nouveau")
        #expect(disliked.ids.count == 500)
        #expect(!disliked.contains("0"))
        #expect(disliked.contains("nouveau"))
    }

    @Test("API : réponse, j'aime, fil, champs du commentaire (ADR-060)")
    func remote() async throws {
        let log = RequestLog()
        let comment =
            #"{"id":"c1","videoId":"v1","parentId":"c0","content":"Oui","createdAt":"2026-10-16T10:00:00.000Z","#
            + #""author":{"id":"bob-id","username":"bob","displayName":"Bob","avatarUrl":null},"#
            + #""repliesCount":0,"likesCount":3,"likedByAuthor":true,"viewer":{"liked":true}}"#
        let repo = RemoteInteractionRepository(
            client: makeClient(
                transport: MockTransport { request, operationID in
                    log.record(request, operationID)
                    switch operationID {
                    case "addComment": return json(.created, comment)
                    case "listReplies": return json(.ok, #"{"items":["# + comment + #"],"nextCursor":null}"#)
                    default: return json(.ok, #"{"active":true,"count":3}"#)
                    }
                }))
        let reply = try await repo.addComment(videoID: "v1", content: "Oui", replyToID: "c0")
        #expect(reply.parentID == "c0")
        #expect(reply.likesCount == 3)
        #expect(reply.likedByAuthor)
        #expect(reply.viewerLiked == true)
        #expect(try await repo.replies(commentID: "c0", cursor: nil).comments == [reply])
        #expect(try await repo.setCommentLike(commentID: "c1", active: true) == InteractionState(active: true, count: 3))
        _ = try await repo.setCommentLike(commentID: "c1", active: false)
        #expect(log.operations == ["addComment", "listReplies", "likeComment", "unlikeComment"])
    }
}

extension VideoComment {
    static func sample(
        _ id: String, videoID: String = "v1", parentID: String? = nil, content: String = "Super", author: UserSummary = .bob,
        repliesCount: Int
    ) -> VideoComment {
        var comment = VideoComment.sample(id, videoID: videoID, content: content, author: author)
        comment.parentID = parentID
        comment.repliesCount = repliesCount
        return comment
    }

    static func sample(_ id: String, parentID: String, author: UserSummary = .bob) -> VideoComment {
        var comment = VideoComment.sample(id, author: author)
        comment.parentID = parentID
        return comment
    }
}
