import Foundation
import Observation

// État des interactions affiché par-dessus les vidéos chargées (feed, vidéo seule) : like, favori, republication,
// partage, follow de l'auteur, nombre de commentaires. Partagé par tous les écrans, pour qu'un like dans l'un
// se voie dans l'autre.
// - Optimiste : l'écran change tout de suite, puis s'aligne sur le compteur renvoyé par l'API ; en cas d'erreur,
//   il revient à l'état d'avant.
// - Mode invité : toute action ouvre la connexion (ADR-010).
// Les actions renvoient un message d'erreur à afficher (nil si tout va bien) : chaque écran l'affiche lui-même.
@MainActor
@Observable
final class VideoInteractionsModel {
    private struct Override {
        var stats: VideoStats
        var viewer: ViewerState?
    }

    private var overrides: [String: Override] = [:]
    // Auteur → suivi ou non (s'applique à toutes ses vidéos).
    private var followOverrides: [String: Bool] = [:]
    // Requêtes en cours (« like-<id> », « follow-<id> ») : un second toucher pendant l'envoi est ignoré.
    private var pending: Set<String> = []

    private let setReaction: SetReactionUseCase
    private let setFollow: SetFollowUseCase
    private let recordShare: ShareVideoUseCase
    private let session: SessionStore

    init(setReaction: SetReactionUseCase, setFollow: SetFollowUseCase, recordShare: ShareVideoUseCase, session: SessionStore) {
        self.setReaction = setReaction
        self.setFollow = setFollow
        self.recordShare = recordShare
        self.session = session
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
    }

    // Bouton cœur, favori ou republication : bascule l'état.
    func toggle(_ kind: ReactionKind, on video: FeedVideo) async -> String? {
        guard session.isSignedIn else { session.requestSignIn(); return nil }
        let active = !(display(video).viewer ?? .empty).isActive(kind)
        return await apply(kind, active: active, on: video)
    }

    // Double toucher : like seulement (ne retire jamais un like), comme TikTok.
    func likeFromDoubleTap(_ video: FeedVideo) async -> String? {
        guard session.isSignedIn else { session.requestSignIn(); return nil }
        guard display(video).viewer?.liked != true else { return nil }
        return await apply(.like, active: true, on: video)
    }

    func toggleFollow(authorOf video: FeedVideo) async -> String? {
        guard session.isSignedIn else { session.requestSignIn(); return nil }
        guard !isOwn(video) else { return nil }
        let key = "follow-\(video.author.id)"
        guard pending.insert(key).inserted else { return nil }
        defer { pending.remove(key) }
        let following = display(video).viewer?.followingAuthor ?? false
        followOverrides[video.author.id] = !following
        do {
            followOverrides[video.author.id] = try await setFollow(username: video.author.username, active: !following).active
            return nil
        } catch {
            followOverrides[video.author.id] = following
            return handle(error)
        }
    }

    // Partage réellement envoyé depuis la feuille de partage : compté, avec le total renvoyé par l'API.
    func shareCompleted(_ video: FeedVideo) async {
        guard let shares = try? await recordShare(videoID: video.id) else { return }
        let current = display(video)
        overrides[video.id] = Override(stats: current.stats.with(shares: shares), viewer: current.viewer)
    }

    // Commentaire ajouté (+1) ou supprimé (-1) depuis la feuille de commentaires.
    func commentsChanged(on video: FeedVideo, by delta: Int) {
        let current = display(video)
        overrides[video.id] = Override(stats: current.stats.with(comments: max(0, current.stats.comments + delta)), viewer: current.viewer)
    }

    private func apply(_ kind: ReactionKind, active: Bool, on video: FeedVideo) async -> String? {
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
            overrides[video.id] = Override(stats: current.stats.with(kind, count: state.count), viewer: (current.viewer ?? .empty).with(kind, active: state.active))
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
