import Foundation
import Observation

// Profil d'un compte (ADR-016) : le sien (onglet Profil) ou celui d'un autre. Assemblé à partir de plusieurs
// routes : profil, relation (compte connecté), grilles au format du feed.
@MainActor
@Observable
final class ProfileViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    // Nil : son propre profil.
    let username: String?
    private(set) var state: State = .loading
    private(set) var relationship: Relationship?
    private(set) var selectedGrid: ProfileGrid = .videos
    private var loadedProfile: UserProfile?
    private var grids: [ProfileGrid: PagedList<FeedVideo>] = [:]

    private let getMyProfile: GetMyProfileUseCase
    private let loadProfile: LoadProfileUseCase
    private let loadRelationship: LoadRelationshipUseCase
    private let loadVideoPage: LoadVideoPageUseCase
    private let setBlocked: SetBlockedUseCase
    private let interactions: VideoInteractionsModel
    private let session: SessionStore

    init(
        username: String?,
        getMyProfile: GetMyProfileUseCase,
        loadProfile: LoadProfileUseCase,
        loadRelationship: LoadRelationshipUseCase,
        loadVideoPage: LoadVideoPageUseCase,
        setBlocked: SetBlockedUseCase,
        interactions: VideoInteractionsModel,
        session: SessionStore
    ) {
        self.username = username
        self.getMyProfile = getMyProfile
        self.loadProfile = loadProfile
        self.loadRelationship = loadRelationship
        self.loadVideoPage = loadVideoPage
        self.setBlocked = setBlocked
        self.interactions = interactions
        self.session = session
    }

    // Son propre profil, y compris ouvert depuis une vidéo ou une liste.
    var isOwn: Bool {
        guard let username else { return true }
        guard let me = session.profile else { return false }
        return username == me.username || loadedProfile?.id == me.id
    }

    var profile: UserProfile? {
        isOwn ? session.profile ?? loadedProfile : loadedProfile
    }

    var availableGrids: [ProfileGrid] {
        ProfileGrid.available(isOwn: isOwn)
    }

    var isBlocked: Bool {
        relationship?.blockedByMe == true
    }

    // Bouton d'abonnement (profil d'un autre compte). En invité : « Suivre », qui ouvre la connexion.
    var followStatus: FollowStatus? {
        guard !isOwn, let profile else { return nil }
        let loaded = relationship?.following ?? false
        return FollowStatus(following: interactions.isFollowing(profile.id, loaded: loaded), followedBy: relationship?.followedBy ?? false)
    }

    func grid(_ grid: ProfileGrid) -> PagedList<FeedVideo> {
        if let list = grids[grid] { return list }
        let list = PagedList<FeedVideo>(session: session) { [weak self] cursor in
            guard let self, let username = self.profile?.username else { return ([], nil) }
            return try await self.loadVideoPage(VideoList(grid, username: username), cursor: cursor).asPage
        }
        grids[grid] = list
        return list
    }

    // Source du lecteur vertical ouvert depuis une grille.
    func videoList(for grid: ProfileGrid) -> VideoList? {
        profile.map { VideoList(grid, username: $0.username) }
    }

    func load() async {
        if profile == nil { state = .loading }
        do {
            if let username, !isOwn {
                loadedProfile = try await loadProfile(username: username)
                if session.isSignedIn, !isOwn {
                    relationship = try await loadRelationship(username: username)
                }
            } else {
                let me = try await getMyProfile()
                loadedProfile = me
                session.update(me)
            }
            state = .loaded
        } catch {
            if let message = handle(error) {
                state = profile == nil ? .failed(message) : .loaded
            }
            return
        }
        if !isBlocked { await grid(selectedGrid).loadFirstIfNeeded() }
    }

    // Tirer pour actualiser : profil, relation et grilles déjà ouvertes.
    func refresh() async {
        await load()
        guard !isBlocked else { return }
        for list in grids.values where list.state != .idle {
            await list.loadFirst()
        }
    }

    func select(_ grid: ProfileGrid) async {
        selectedGrid = grid
        await self.grid(grid).loadFirstIfNeeded()
    }

    // Vidéos supprimées depuis un lecteur : retirées des grilles.
    func removeVideos(_ ids: Set<String>) {
        for list in grids.values {
            list.remove { ids.contains($0.id) }
        }
    }

    func toggleFollow() async -> String? {
        guard let profile, let status = followStatus else { return nil }
        switch await interactions.setFollowing(profile.summary, active: !status.isFollowing, wasFollowing: status.isFollowing) {
        case .done(let followers):
            loadedProfile = profile.with(followersCount: followers)
            return nil
        case .failed(let message):
            return message
        case .ignored:
            return nil
        }
    }

    // Bloquer supprime les follows dans les deux sens ; débloquer ne rétablit rien.
    func setBlocked(_ blocked: Bool) async -> String? {
        guard let profile, !isOwn else { return nil }
        do {
            try await setBlocked(blocked, username: profile.username)
            relationship = Relationship(following: false, followedBy: blocked ? false : relationship?.followedBy ?? false, blockedByMe: blocked)
            if blocked { interactions.blocked(profile.id) }
            await refresh()
            return nil
        } catch {
            return handle(error)
        }
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        if error == .notFound { return "Ce compte n’existe pas ou plus." }
        return error.message
    }
}

extension UserProfile {
    func with(followersCount: Int) -> UserProfile {
        UserProfile(id: id, username: username, displayName: displayName, avatarURL: avatarURL, bio: bio,
                    followersCount: followersCount, followingCount: followingCount, createdAt: createdAt)
    }

    var summary: UserSummary {
        UserSummary(id: id, username: username, displayName: displayName, avatarURL: avatarURL)
    }
}
