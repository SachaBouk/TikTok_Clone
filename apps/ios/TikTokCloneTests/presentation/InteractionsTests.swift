import Foundation
import Testing
import UIKit

@testable import TikTokClone

@MainActor
@Suite("Interactions : modèle partagé, commentaires, vidéo seule")
struct InteractionsTests {
    let repository = FakeInteractionRepository()
    let videos = FakeVideoPublishingRepository()
    // Événements envoyés (mesure d'audience acceptée).
    let analyticsService = FakeAnalyticsService()
    var analytics: AnalyticsModel { makeAnalytics(analyticsService) }

    func makeModel(signedIn: Bool = true) async -> (VideoInteractionsModel, SessionStore) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let model = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: repository),
            setFollow: SetFollowUseCase(interactions: repository),
            recordShare: ShareVideoUseCase(interactions: repository),
            deleteVideo: DeleteVideoUseCase(videos: videos),
            session: session,
            analytics: analytics
        )
        return (model, session)
    }

    // Vidéo de bob, vue par alice (connectée) : 2 likes au départ.
    let video = FeedVideo.sample("v1", viewer: .empty)

    @Test("like : affichage optimiste puis compteur de l'API ; second toucher : retrait")
    func toggleLike() async {
        let (model, _) = await makeModel()
        repository.setServerCount(2, for: "like-v1")
        #expect(await model.toggle(.like, on: video) == nil)
        #expect(model.display(video).viewer?.liked == true)
        #expect(model.display(video).stats.likes == 3)
        #expect(await model.toggle(.like, on: video) == nil)
        #expect(model.display(video).viewer?.liked == false)
        #expect(model.display(video).stats.likes == 2)
        #expect(repository.calls == ["like-v1-true", "like-v1-false"])
    }

    @Test("le compteur s'aligne sur l'API (d'autres ont liké entre-temps)")
    func serverCountWins() async {
        let (model, _) = await makeModel()
        repository.setServerCount(9, for: "favorite-v1")
        _ = await model.toggle(.favorite, on: video)
        #expect(model.display(video).stats.favorites == 10)
        #expect(model.display(video).viewer?.favorited == true)
    }

    @Test("échec : retour à l'état d'avant et message (blocage)")
    func failureReverts() async {
        let (model, _) = await makeModel()
        repository.fail(with: .blocked)
        let message = await model.toggle(.repost, on: video)
        #expect(message == AppError.blocked.message)
        #expect(model.display(video) == video)
    }

    @Test("double toucher : like seulement, jamais de retrait")
    func doubleTap() async {
        let (model, _) = await makeModel()
        _ = await model.likeFromDoubleTap(video)
        _ = await model.likeFromDoubleTap(video)
        #expect(repository.calls == ["like-v1-true"])
        #expect(model.display(video).viewer?.liked == true)
    }

    @Test("un second toucher pendant l'envoi est ignoré")
    func ignoresWhilePending() async {
        let (model, _) = await makeModel()
        repository.state.withLock { $0.delay = .milliseconds(50) }
        async let first = model.toggle(.like, on: video)
        try? await Task.sleep(for: .milliseconds(10))
        let second = await model.toggle(.like, on: video)
        _ = await first
        #expect(second == nil)
        #expect(repository.calls == ["like-v1-true"])
    }

    @Test("invité : ouvre la connexion, aucun appel")
    func guestPromptsSignIn() async {
        let (model, session) = await makeModel(signedIn: false)
        _ = await model.toggle(.like, on: FeedVideo.sample("v1"))
        _ = await model.toggleFollow(authorOf: FeedVideo.sample("v1"))
        #expect(session.isPresentingSignIn)
        #expect(repository.calls.isEmpty)
    }

    @Test("session expirée : retour en invité, pas de message d'erreur")
    func sessionExpired() async {
        let (model, session) = await makeModel()
        repository.fail(with: .sessionExpired)
        #expect(await model.toggle(.like, on: video) == nil)
        #expect(!session.isSignedIn)
    }

    @Test("follow : toutes les vidéos de l'auteur ; pas sur ses propres vidéos")
    func follow() async {
        let (model, _) = await makeModel()
        let other = FeedVideo.sample("v2", viewer: .empty)
        _ = await model.toggleFollow(authorOf: video)
        #expect(model.display(video).viewer?.followingAuthor == true)
        #expect(model.display(other).viewer?.followingAuthor == true)
        #expect(repository.calls == ["follow-bob-true"])

        let own = FeedVideo.sample("v3", author: "alice", viewer: .empty)
        let ownVideo = FeedVideo(
            id: own.id, description: nil, hlsURL: own.hlsURL, thumbnailURL: own.thumbnailURL, createdAt: own.createdAt,
            stats: own.stats, author: .alice, viewer: .empty)
        #expect(model.isOwn(ownVideo))
        _ = await model.toggleFollow(authorOf: ownVideo)
        #expect(repository.calls == ["follow-bob-true"])
    }

    @Test("feed des abonnements (ADR-048) : abonnements faits comptés, échec et blocage compris")
    func followsVersion() async {
        let (model, _) = await makeModel()
        #expect(model.followsVersion == 0)
        _ = await model.toggleFollow(authorOf: video)
        #expect(model.followsVersion == 1)
        repository.fail(with: .network)
        _ = await model.toggleFollow(authorOf: video)
        #expect(model.followsVersion == 1)
        model.blocked("dave-id")
        #expect(model.followsVersion == 2)
        // Données rechargées : la version ne revient pas en arrière.
        model.reset()
        #expect(model.followsVersion == 2)
    }

    @Test("partage envoyé : compté avec le total de l'API ; commentaires ajustés ; reset")
    func shareAndComments() async {
        let (model, _) = await makeModel()
        await model.shareCompleted(video)
        #expect(model.display(video).stats.shares == 1)
        model.commentsChanged(on: video, by: 1)
        #expect(model.display(video).stats.comments == video.stats.comments + 1)
        model.reset()
        #expect(model.display(video) == video)
    }

    @Test("commentaires : pages, envoi nettoyé, suppression du sien, compteur")
    func comments() async {
        let (_, session) = await makeModel()
        repository.state.withLock { $0.comments["v1"] = [.sample("c1"), .sample("c2"), .sample("c3", author: .alice)] }
        var deltas: [Int] = []
        let viewModel = CommentsViewModel(
            video: video,
            loadComments: LoadCommentsUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository),
            session: session,
            analytics: analytics,
            onCountChange: { deltas.append($0) }
        )
        await viewModel.start()
        #expect(viewModel.comments.map(\.id) == ["c1", "c2"])
        #expect(viewModel.hasMore)
        await viewModel.loadMore()
        #expect(viewModel.comments.map(\.id) == ["c1", "c2", "c3"])
        #expect(!viewModel.hasMore)

        viewModel.draft = "   "
        #expect(!viewModel.canSend)
        viewModel.draft = String(repeating: "a", count: 501)
        #expect(!viewModel.canSend)
        viewModel.draft = "  Trop bien  "
        await viewModel.send()
        #expect(viewModel.comments.first?.content == "Trop bien")
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.count == video.stats.comments + 1)

        #expect(!viewModel.isOwn(viewModel.comments[1]))
        let own = viewModel.comments.first { $0.id == "c3" }!
        await viewModel.delete(own)
        #expect(!viewModel.comments.contains(own))
        #expect(deltas == [1, -1])
    }

    @Test("commentaires : sur sa propre vidéo, ceux des autres se suppriment aussi (ADR-042) ; pas sur la vidéo d'un autre")
    func deleteOnOwnVideo() async {
        let (_, session) = await makeModel()
        repository.state.withLock { $0.comments["mine"] = [.sample("c1", videoID: "mine"), .sample("c2", videoID: "mine", author: .alice)] }
        let sample = FeedVideo.sample("mine")
        // Vidéo d'alice, le compte connecté.
        let mine = FeedVideo(
            id: sample.id, description: sample.description, hlsURL: sample.hlsURL, thumbnailURL: sample.thumbnailURL,
            createdAt: sample.createdAt, stats: sample.stats, author: .alice, viewer: sample.viewer)
        let viewModel = CommentsViewModel(
            video: mine, loadComments: LoadCommentsUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository), session: session, analytics: analytics, onCountChange: { _ in })
        await viewModel.start()
        let others = viewModel.comments[0]
        #expect(viewModel.isOwnVideo)
        #expect(!viewModel.isOwn(others))
        #expect(viewModel.canDelete(others))
        await viewModel.delete(others)
        #expect(viewModel.comments.map(\.id) == ["c2"])

        // Sur la vidéo de bob, le commentaire de bob ne se supprime pas.
        let onBob = CommentsViewModel(
            video: video, loadComments: LoadCommentsUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository), session: session, analytics: analytics, onCountChange: { _ in })
        #expect(!onBob.isOwnVideo)
        #expect(!onBob.canDelete(.sample("c9")))
    }

    @Test("commentaires : suppression refusée → le commentaire revient à sa place")
    func deleteFailure() async {
        let (_, session) = await makeModel()
        repository.state.withLock { $0.comments["v1"] = [.sample("c1", author: .alice)] }
        let viewModel = CommentsViewModel(
            video: video, loadComments: LoadCommentsUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository), session: session, analytics: analytics, onCountChange: { _ in })
        await viewModel.start()
        repository.fail(with: .network)
        await viewModel.delete(viewModel.comments[0])
        #expect(viewModel.comments.map(\.id) == ["c1"])
        #expect(viewModel.errorMessage == AppError.network.message)
    }

    @Test("commentaires : ceux d'un compte bloqué depuis la feuille disparaissent, le nombre affiché reste celui de l'API")
    func commentsOfBlockedAccount() async {
        let (_, session) = await makeModel()
        repository.state.withLock { $0.comments["v1"] = [.sample("c1"), .sample("c2", author: .alice)] }
        let viewModel = CommentsViewModel(
            video: video, loadComments: LoadCommentsUseCase(interactions: repository),
            addComment: AddCommentUseCase(interactions: repository),
            deleteComment: DeleteCommentUseCase(interactions: repository), session: session, analytics: analytics, onCountChange: { _ in })
        await viewModel.start()
        viewModel.removeComments(byAuthors: [UserSummary.bob.id])
        #expect(viewModel.comments.map(\.id) == ["c2"])
        #expect(viewModel.count == video.stats.comments)
    }

    @Test("vidéo seule : chargée, lue, vue comptée ; introuvable → message")
    func videoDetail() async throws {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let playback = FakePlayback()
        let history = FakeViewHistoryRepository()
        let feed = FakeFeedRepository([])
        feed.videos["v1"] = video
        let viewModel = VideoDetailViewModel(
            videoID: "v1", loadVideo: LoadVideoUseCase(feed: feed), recordView: RecordViewUseCase(history: history),
            playback: playback, session: session, analytics: analytics, viewDelay: .milliseconds(20))
        await viewModel.start()
        #expect(viewModel.video == video)
        #expect(playback.loaded == [["v1"]])
        #expect(playback.played == ["v1"])
        try await Task.sleep(for: .milliseconds(120))
        #expect(history.recorded == ["v1"])

        // Vidéo signalée : arrêtée sous le voile, reprise une fois affichée.
        viewModel.setMasked(true)
        viewModel.togglePause()
        #expect(!viewModel.isPaused)
        viewModel.resume()
        #expect(playback.played == ["v1"])
        viewModel.setMasked(false)
        #expect(playback.played == ["v1", "v1"])

        let missing = VideoDetailViewModel(
            videoID: "absente", loadVideo: LoadVideoUseCase(feed: feed), recordView: RecordViewUseCase(history: history),
            playback: playback, session: session, analytics: analytics)
        await missing.start()
        #expect(missing.state == .failed(AppError.notFound.message))
    }

    @Test("partage : message et lien séparés, sauf pour « Copier » où le message contient le lien")
    func shareContent() {
        let content = VideoShareContent(video: .sample("01a0d86f-1c2b-7000-8000-000000000001"))
        let link = URL(string: "tiktokclone://videos/01a0d86f-1c2b-7000-8000-000000000001")!
        #expect(content.text(for: .message) == "Regarde cette vidéo de @bob sur TikTok Clone")
        #expect(content.link(for: .message) == link)
        #expect(content.link(for: nil) == link)
        #expect(content.text(for: .copyToPasteboard) == "Regarde cette vidéo de @bob sur TikTok Clone : \(link.absoluteString)")
        #expect(content.link(for: .copyToPasteboard) == nil)
        #expect(content.activityItems.count == 2)
    }

    @Test("lien d'app : construit, reconnu, ouvert par le routeur")
    func videoLink() {
        let id = "01a0d86f-1c2b-7000-8000-000000000001"
        let url = VideoLink.url(for: id)
        #expect(url.absoluteString == "tiktokclone://videos/\(id)")
        #expect(VideoLink.videoID(from: url) == id)
        #expect(VideoLink.videoID(from: URL(string: "tiktokclone://videos/pas-un-uuid")!) == nil)
        #expect(VideoLink.videoID(from: URL(string: "https://exemple.fr/videos/\(id)")!) == nil)
        let router = AppRouter()
        #expect(router.open(url))
        #expect(router.presentedVideo?.id == id)
        #expect(!router.open(URL(string: "tiktokclone://profil/alice")!))
    }

    @Test("règles des commentaires")
    func commentRules() {
        #expect(CommentRules.sanitized("  Bonjour \n") == "Bonjour")
        #expect(CommentRules.sanitized(" \n ") == nil)
        #expect(CommentRules.sanitized(String(repeating: "é", count: 500)) != nil)
        #expect(CommentRules.sanitized(String(repeating: "é", count: 501)) == nil)
    }
}
