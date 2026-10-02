import Foundation
import Observation

// État des interactions affiché par-dessus les vidéos chargées (feed, vidéo seule) : like, favori, republication,
// partage, follow de l'auteur, nombre de commentaires. Partagé par tous les écrans, pour qu'un like dans l'un
// se voie dans l'autre.
// - Optimiste : l'écran change tout de suite, puis s'aligne sur le compteur renvoyé par l'API ; en cas d'erreur,
//   il revient à l'état d'avant.
// - Mode invité : toute action ouvre la connexion (ADR-010).
// Les actions renvoient un message d'erreur à afficher (nil si tout va bien) : chaque écran l'affiche lui-même.
// Le suivi d'un compte est partagé de la même façon avec les profils et les listes d'abonnés.
// Mesure d'audience (ADR-013) : chaque réaction, follow et partage réussi est envoyé (engagement).
@MainActor
@Observable
final class VideoInteractionsModel {
    enum FollowOutcome: Equatable {
        // Nouveau nombre d'abonnés du compte suivi.
        case done(followers: Int)
        case failed(String)
        // Invité (la connexion s'ouvre), requête déjà en cours, ou session expirée.
        case ignored
    }

    private struct Override {
        var stats: VideoStats
        var viewer: ViewerState?
    }

    private var overrides: [String: Override] = [:]
    // Auteur → suivi ou non (s'applique à toutes ses vidéos).
    private var followOverrides: [String: Bool] = [:]
    // Requêtes en cours (« like-<id> », « follow-<id> ») : un second toucher pendant l'envoi est ignoré.
    private var pending: Set<String> = []
    // Vidéos supprimées par leur auteur depuis leur chargement : les écrans les retirent.
    private(set) var deletedVideoIDs: Set<String> = []
    // Comptes bloqués depuis le chargement des écrans : ceux-ci retirent leurs vidéos, commentaires et lignes,
    // que l'API ne renvoie plus (blocage dans les deux sens). Débloquer retire le compte de l'ensemble.
    private(set) var blockedUserIDs: Set<String> = []

    private let setReaction: SetReactionUseCase
    private let setFollow: SetFollowUseCase
    private let recordShare: ShareVideoUseCase
    private let deleteVideo: DeleteVideoUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(
        setReaction: SetReactionUseCase,
        setFollow: SetFollowUseCase,
        recordShare: ShareVideoUseCase,
        deleteVideo: DeleteVideoUseCase,
        session: SessionStore,
        analytics: AnalyticsModel
    ) {
        self.setReaction = setReaction
        self.setFollow = setFollow
        self.recordShare = recordShare
        self.deleteVideo = deleteVideo
        self.session = session
        self.analytics = analytics
    }

    // La vidéo telle qu'à afficher : données chargées + changements faits depuis.
    func display(_ video: FeedVideo) -> FeedVideo {
        var result = video
        if let override = overrides[video.id] { result = result.with(stats: override.stats, viewer: override.viewer) }
        if let following = followOverrides[video.author.id] {
            result = result.with(viewer: (result.viewer ?? .empty).with(followingAuthor: following))
        }
        return result
    }

    // Le compte connecté est-il l'auteur ? (pas de bouton « Suivre » sur ses propres vidéos)
    func isOwn(_ video: FeedVideo) -> Bool {
        session.profile?.id == video.author.id
    }

    // Données fraîches rechargées (nouvelle session du feed, connexion) : on repart de l'API.
    func reset() {
        overrides.removeAll()
        followOverrides.removeAll()
        blockedUserIDs.removeAll()
    }

    // Bouton cœur, favori ou republication : bascule l'état.
    func toggle(_ kind: ReactionKind, on video: FeedVideo) async -> String? {
        guard session.isSignedIn else {
            session.requestSignIn()
            return nil
        }
        let active = !(display(video).viewer ?? .empty).isActive(kind)
        return await apply(kind, active: active, on: video)
    }

    // Double toucher : like seulement (ne retire jamais un like), comme TikTok.
    func likeFromDoubleTap(_ video: FeedVideo) async -> String? {
        guard session.isSignedIn else {
            session.requestSignIn()
            return nil
        }
        guard display(video).viewer?.liked != true else { return nil }
        return await apply(.like, active: true, on: video, doubleTap: true)
    }

    func toggleFollow(authorOf video: FeedVideo) async -> String? {
        guard !isOwn(video) else { return nil }
        let following = display(video).viewer?.followingAuthor ?? false
        if case .failed(let message) = await setFollowing(video.author, active: !following, wasFollowing: following) { return message }
        return nil
    }

    // Le compte connecté suit-il ce compte ? Changement fait depuis le chargement, sinon l'état chargé.
    func isFollowing(_ userID: String, loaded: Bool) -> Bool {
        followOverrides[userID] ?? loaded
    }

    // Suivre ou ne plus suivre un compte (profil, liste d'abonnés, feed) ; optimiste, comme les réactions.
    func setFollowing(_ user: UserSummary, active: Bool, wasFollowing: Bool) async -> FollowOutcome {
        guard session.isSignedIn else {
            session.requestSignIn()
            return .ignored
        }
        guard session.profile?.id != user.id else { return .ignored }
        let key = "follow-\(user.id)"
        guard pending.insert(key).inserted else { return .ignored }
        defer { pending.remove(key) }
        followOverrides[user.id] = active
        do {
            let state = try await setFollow(username: user.username, active: active)
            followOverrides[user.id] = state.active
            analytics.track(.followChanged(userID: user.id, active: state.active))
            return .done(followers: state.count)
        } catch {
            followOverrides[user.id] = wasFollowing
            return handle(error).map(FollowOutcome.failed) ?? .ignored
        }
    }

    // Compte bloqué : les follows sont supprimés dans les deux sens par l'API, et ses contenus disparaissent des écrans.
    func blocked(_ userID: String) {
        followOverrides[userID] = false
        blockedUserIDs.insert(userID)
    }

    // Compte débloqué (profil ou réglages) : ses contenus reviendront au prochain chargement.
    func unblocked(_ userID: String) {
        blockedUserIDs.remove(userID)
    }

    // Suppression d'une de ses vidéos, quel que soit l'écran (feed, lecteur d'une grille, vidéo seule).
    func delete(_ video: FeedVideo) async -> String? {
        guard isOwn(video) else { return nil }
        do {
            try await deleteVideo(id: video.id)
            deletedVideoIDs.insert(video.id)
            return nil
        } catch {
            return handle(error)
        }
    }

    // Partage réellement envoyé depuis la feuille de partage : compté, avec le total renvoyé par l'API.
    func shareCompleted(_ video: FeedVideo) async {
        guard let shares = try? await recordShare(videoID: video.id) else { return }
        analytics.track(.videoShared(videoID: video.id, byMessage: false))
        let current = display(video)
        overrides[video.id] = Override(stats: current.stats.with(shares: shares), viewer: current.viewer)
    }

    // Vidéo envoyée par message : l'API l'a déjà comptée comme un partage (+1 à l'écran).
    func sharedByMessage(_ video: FeedVideo) {
        analytics.track(.videoShared(videoID: video.id, byMessage: true))
        let current = display(video)
        overrides[video.id] = Override(stats: current.stats.with(shares: current.stats.shares + 1), viewer: current.viewer)
    }

    // Commentaire ajouté (+1) ou supprimé (-1) depuis la feuille de commentaires.
    func commentsChanged(on video: FeedVideo, by delta: Int) {
        let current = display(video)
        overrides[video.id] = Override(stats: current.stats.with(comments: max(0, current.stats.comments + delta)), viewer: current.viewer)
    }

    private func apply(_ kind: ReactionKind, active: Bool, on video: FeedVideo, doubleTap: Bool = false) async -> String? {
        let key = "\(kind)-\(video.id)"
        guard pending.insert(key).inserted else { return nil }
        defer { pending.remove(key) }

        let before = display(video)
        let viewer = before.viewer ?? .empty
        let optimistic = max(0, before.stats.count(of: kind) + (active ? 1 : -1))
        overrides[video.id] = Override(stats: before.stats.with(kind, count: optimistic), viewer: viewer.with(kind, active: active))
        do {
            let state = try await setReaction(kind, videoID: video.id, active: active)
            let current = display(video)
            overrides[video.id] = Override(
                stats: current.stats.with(kind, count: state.count), viewer: (current.viewer ?? .empty).with(kind, active: state.active))
            analytics.track(.videoReaction(kind, active: state.active, videoID: video.id, doubleTap: doubleTap))
            return nil
        } catch {
            overrides[video.id] = Override(stats: before.stats, viewer: before.viewer)
            return handle(error)
        }
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }
}
