import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Profil : écrans")
struct ProfileViewModelTests {
    let profiles = FakeProfileRepository()
    let relationships = FakeRelationshipRepository()
    let videoLists = FakeVideoListRepository()
    let interactionRepository = FakeInteractionRepository()
    let publishingRepository = FakeVideoPublishingRepository()

    func makeSession(signedIn: Bool = true) async -> SessionStore {
        let session = TikTokCloneTests.makeSession(auth: FakeAuthRepository(hasSession: signedIn), profiles: profiles)
        await session.restore()
        return session
    }

    func makeInteractions(_ session: SessionStore) -> VideoInteractionsModel {
        VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: publishingRepository),
            session: session,
            analytics: makeAnalytics()
        )
    }

    func makeProfile(_ username: String?, session: SessionStore, interactions: VideoInteractionsModel? = nil) -> ProfileViewModel {
        ProfileViewModel(
            username: username,
            getMyProfile: GetMyProfileUseCase(profiles: profiles),
            loadProfile: LoadProfileUseCase(profiles: profiles),
            loadRelationship: LoadRelationshipUseCase(relationships: relationships),
            loadVideoPage: LoadVideoPageUseCase(videos: videoLists),
            setBlocked: SetBlockedUseCase(relationships: relationships),
            interactions: interactions ?? makeInteractions(session),
            session: session
        )
    }

    @Test("son profil : relu et partagé avec la session ; 4 grilles, chargées à la demande")
    func ownProfile() async {
        let session = await makeSession()
        videoLists.set(.accountVideos(username: "alice"), [page(["v1", "v2"], next: nil)])
        let viewModel = makeProfile(nil, session: session)
        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.isOwn)
        #expect(viewModel.availableGrids.count == 4)
        #expect(viewModel.followStatus == nil)
        #expect(viewModel.grid(.videos).items.map(\.id) == ["v1", "v2"])
        #expect(videoLists.requests == ["accountVideos(username: \"alice\")-nil"])

        await viewModel.select(.likes)
        #expect(videoLists.requests.last == "myLikes-nil")
        await viewModel.select(.videos)
        #expect(videoLists.requests.count == 2)
    }

    @Test("profil d'un autre compte : relation, bouton d'abonnement, abonnés mis à jour après le follow")
    func otherProfile() async {
        let session = await makeSession()
        profiles.state.withLock { $0.others["bob"] = .bob }
        relationships.state.withLock { $0.relationships["bob"] = Relationship(following: false, followedBy: true, blockedByMe: false) }
        interactionRepository.state.withLock { $0.followers = 10 }
        let viewModel = makeProfile("bob", session: session)
        await viewModel.load()
        #expect(!viewModel.isOwn)
        #expect(viewModel.availableGrids == [.videos, .reposts])
        #expect(viewModel.followStatus == .followBack)

        #expect(await viewModel.toggleFollow() == nil)
        #expect(viewModel.followStatus == .friends)
        #expect(viewModel.profile?.followersCount == 11)
        #expect(interactionRepository.calls == ["follow-bob-true"])
    }

    @Test("invité : pas de relation ; « Suivre » ouvre la connexion")
    func guest() async {
        let session = await makeSession(signedIn: false)
        profiles.state.withLock { $0.others["bob"] = .bob }
        let viewModel = makeProfile("bob", session: session)
        await viewModel.load()
        #expect(viewModel.followStatus == .follow)
        #expect(relationships.calls.isEmpty)
        _ = await viewModel.toggleFollow()
        #expect(session.isPresentingSignIn)
        #expect(interactionRepository.calls.isEmpty)
    }

    @Test("son pseudo ouvert depuis une vidéo : c'est son profil")
    func ownProfileByUsername() async {
        let session = await makeSession()
        let viewModel = makeProfile("alice", session: session)
        await viewModel.load()
        #expect(viewModel.isOwn)
        #expect(relationships.calls.isEmpty)
    }

    @Test("compte inconnu : message")
    func notFound() async {
        let session = await makeSession()
        let viewModel = makeProfile("inconnu", session: session)
        await viewModel.load()
        #expect(viewModel.state == .failed("Ce compte n’existe pas ou plus."))
    }

    @Test("bloquer : relation mise à jour, follow retiré partout, grilles masquées")
    func block() async {
        let session = await makeSession()
        profiles.state.withLock { $0.others["bob"] = .bob }
        relationships.state.withLock { $0.relationships["bob"] = Relationship(following: true, followedBy: true, blockedByMe: false) }
        let interactions = makeInteractions(session)
        let viewModel = makeProfile("bob", session: session, interactions: interactions)
        await viewModel.load()
        relationships.state.withLock { $0.relationships["bob"] = Relationship(following: false, followedBy: false, blockedByMe: true) }
        #expect(await viewModel.setBlocked(true) == nil)
        #expect(viewModel.isBlocked)
        #expect(!interactions.isFollowing("bob-id", loaded: true))
        #expect(relationships.calls.contains("block-bob"))
        // Les écrans retirent ses contenus ; débloquer le retire de l'ensemble.
        #expect(interactions.blockedUserIDs == ["bob-id"])
        relationships.state.withLock { $0.relationships["bob"] = Relationship(following: false, followedBy: false, blockedByMe: false) }
        #expect(await viewModel.setBlocked(false) == nil)
        #expect(interactions.blockedUserIDs.isEmpty)
    }

    @Test("vidéo supprimée depuis un lecteur : retirée des grilles")
    func removeVideos() async {
        let session = await makeSession()
        videoLists.set(.accountVideos(username: "alice"), [page(["v1", "v2"], next: nil)])
        let viewModel = makeProfile(nil, session: session)
        await viewModel.load()
        viewModel.removeVideos(["v1"])
        #expect(viewModel.grid(.videos).items.map(\.id) == ["v2"])
    }

    @Test("compte bloqué depuis un autre écran : ses vidéos quittent les grilles")
    func removeBlockedAuthors() async {
        let session = await makeSession()
        videoLists.set(.myLikes, [FeedPage(videos: [.sample("v1", author: "bob"), .sample("v2", author: "carol")], nextCursor: nil)])
        let viewModel = makeProfile(nil, session: session)
        await viewModel.load()
        await viewModel.select(.likes)
        viewModel.removeVideos(byAuthors: ["bob-id"])
        #expect(viewModel.grid(.likes).items.map(\.id) == ["v2"])
    }

    @Test("modifier le profil : seuls les champs changés ; pseudo pris : message ; photo recadrée puis envoyée")
    func editProfile() async {
        let session = await makeSession()
        let transport = FakeAvatarTransport()
        let viewModel = EditProfileViewModel(
            updateProfile: UpdateProfileUseCase(profiles: profiles),
            changeAvatar: ChangeAvatarUseCase(profiles: profiles, transport: transport),
            removeAvatar: RemoveAvatarUseCase(profiles: profiles),
            session: session,
            prepareImage: { _ in Data(count: 2000) }
        )
        #expect(!viewModel.hasChanges)
        viewModel.displayName = "Alice M."
        #expect(viewModel.hasChanges)
        #expect(await viewModel.save())
        #expect(profiles.updates == [ProfileChanges(displayName: "Alice M.")])
        #expect(session.profile?.displayName == "Alice M.")

        profiles.fail(with: .rejected("Ce pseudo est déjà pris."))
        viewModel.username = "bob"
        #expect(await !viewModel.save())
        #expect(viewModel.errorMessage == "Ce pseudo est déjà pris.")

        profiles.fail(with: nil)
        await viewModel.changePhoto(Data([1, 2, 3]))
        #expect(transport.count == 1)
        #expect(session.profile?.avatarURL != nil)
        await viewModel.removePhoto()
        #expect(session.profile?.avatarURL == nil)
    }

    @Test("paramètres : déconnexion ; suppression du compte, envois oubliés, retour en invité")
    func accountSettings() async throws {
        let session = await makeSession()
        let store = InMemoryUploadStore()
        try store.save(.sample(id: "u1"))
        let viewModel = AccountSettingsViewModel(
            deleteAccount: DeleteAccountUseCase(profiles: profiles, auth: FakeAuthRepository(hasSession: true)),
            discardUploads: DiscardUploadsUseCase(store: store),
            session: session
        )
        await viewModel.deleteMyAccount()
        #expect(profiles.calls == ["deleteAccount"])
        #expect(store.uploads.isEmpty)
        #expect(session.state == .guest)
        #expect(session.notice == nil)

        let other = await makeSession()
        await AccountSettingsViewModel(
            deleteAccount: DeleteAccountUseCase(profiles: profiles, auth: FakeAuthRepository()),
            discardUploads: DiscardUploadsUseCase(store: store),
            session: other
        ).signOut()
        #expect(other.state == .guest)
    }

    @Test("suppression du compte en échec : message, session gardée")
    func accountDeletionFails() async {
        let session = await makeSession()
        profiles.fail(with: .network)
        let viewModel = AccountSettingsViewModel(
            deleteAccount: DeleteAccountUseCase(profiles: profiles, auth: FakeAuthRepository(hasSession: true)),
            discardUploads: DiscardUploadsUseCase(store: InMemoryUploadStore()),
            session: session
        )
        await viewModel.deleteMyAccount()
        #expect(viewModel.errorMessage == AppError.network.message)
        #expect(session.isSignedIn)
    }

    @Test("abonnés : pas de bouton sur son propre compte ; suivre depuis la liste")
    func followList() async {
        let session = await makeSession()
        let me = UserSummary.alice
        relationships.state.withLock {
            $0.follows[.followers] = [
                FollowEntry(user: me, followedAt: .now, viewer: FollowViewer(following: false, followedBy: false)),
                FollowEntry(user: .bob, followedAt: .now, viewer: FollowViewer(following: false, followedBy: true)),
            ]
        }
        let interactions = makeInteractions(session)
        let viewModel = FollowListViewModel(
            kind: .followers, username: "alice", loadFollows: LoadFollowsUseCase(relationships: relationships),
            interactions: interactions, session: session)
        await viewModel.list.loadFirst()
        #expect(viewModel.status(of: viewModel.list.items[0]) == nil)
        #expect(viewModel.status(of: viewModel.list.items[1]) == .followBack)
        await viewModel.toggleFollow(viewModel.list.items[1])
        #expect(viewModel.status(of: viewModel.list.items[1]) == .friends)

        // Bloqué depuis son profil, ouvert depuis la liste : sa ligne disparaît.
        interactions.blocked(UserSummary.bob.id)
        #expect(viewModel.blockedUserIDs == [UserSummary.bob.id])
        viewModel.removeBlocked(viewModel.blockedUserIDs)
        #expect(viewModel.list.items.map(\.user) == [me])
    }

    @Test("comptes bloqués : débloquer retire la ligne, et le compte des contenus masqués")
    func blockedAccounts() async {
        let session = await makeSession()
        relationships.state.withLock { $0.blocked = [.bob] }
        let interactions = makeInteractions(session)
        interactions.blocked(UserSummary.bob.id)
        let viewModel = BlockedAccountsViewModel(
            loadBlockedUsers: LoadBlockedUsersUseCase(relationships: relationships),
            setBlocked: SetBlockedUseCase(relationships: relationships), interactions: interactions, session: session)
        await viewModel.load()
        #expect(viewModel.users == [.bob])
        await viewModel.unblock(.bob)
        #expect(viewModel.users.isEmpty)
        #expect(relationships.calls == ["unblock-bob"])
        #expect(interactions.blockedUserIDs.isEmpty)
    }

    @Test("historique des commentaires : ceux sur les vidéos d'un compte bloqué disparaissent")
    func commentHistoryBlocked() async {
        let session = await makeSession()
        let video = { (author: UserSummary) in CommentHistoryEntry.Video(id: "v-\(author.username)", thumbnailURL: nil, author: author) }
        interactionRepository.state.withLock {
            $0.myComments = [
                CommentHistoryEntry(id: "c1", content: "Un", createdAt: .now, video: video(.bob)),
                CommentHistoryEntry(id: "c2", content: "Deux", createdAt: .now, video: video(.alice)),
            ]
        }
        let interactions = makeInteractions(session)
        let viewModel = CommentHistoryViewModel(
            loadComments: LoadCommentHistoryUseCase(interactions: interactionRepository),
            deleteComment: DeleteCommentUseCase(interactions: interactionRepository),
            interactions: interactions, session: session)
        await viewModel.list.loadFirst()
        interactions.blocked(UserSummary.bob.id)
        viewModel.removeBlocked(viewModel.blockedUserIDs)
        #expect(viewModel.list.items.map(\.id) == ["c2"])
    }

    @Test("historique de visionnage : retirer une vidéo, tout effacer")
    func viewHistory() async {
        let session = await makeSession()
        videoLists.set(.myHistory, [page(["v1", "v2"], next: nil)])
        let viewModel = ViewHistoryViewModel(
            loadVideoPage: LoadVideoPageUseCase(videos: videoLists),
            removeFromHistory: RemoveFromHistoryUseCase(videos: videoLists),
            clearHistory: ClearHistoryUseCase(videos: videoLists),
            session: session
        )
        await viewModel.list.loadFirst()
        await viewModel.remove(viewModel.list.items[0])
        #expect(viewModel.list.items.map(\.id) == ["v2"])
        await viewModel.clear()
        #expect(viewModel.list.items.isEmpty)
        #expect(videoLists.state.withLock { ($0.removed, $0.cleared) } == (["v1"], 1))
    }

    @Test("liste paginée : page suivante à l'approche de la fin, sans doublon ; session expirée → invité")
    func pagedList() async {
        let session = await makeSession()
        videoLists.set(.myLikes, [page((1...10).map { "v\($0)" }, next: "1"), page(["v10", "v11"], next: nil)])
        let list = PagedList<FeedVideo>(session: session) { cursor in
            try await LoadVideoPageUseCase(videos: videoLists)(.myLikes, cursor: cursor).asPage
        }
        await list.loadFirst()
        await list.loadMore(ifNeededAfter: list.items[0])
        #expect(list.items.count == 10)
        await list.loadMore(ifNeededAfter: list.items[5])
        #expect(list.items.map(\.id).suffix(2) == ["v10", "v11"])
        #expect(list.items.count == 11)
        await list.loadMore()
        #expect(videoLists.requests.count == 2)

        let expired = PagedList<FeedVideo>(session: session) { _ in throw AppError.sessionExpired }
        await expired.loadFirst()
        #expect(session.state == .guest)
    }

    @Test("pages vides suivies d'autres (contenus masqués) : la suivante est lue aussitôt, au plus 3 fois de suite")
    func emptyPagesSkipped() async {
        let session = await makeSession()
        let empty = { (next: String?) in FeedPage(videos: [], nextCursor: next) }
        videoLists.set(
            .myLikes, [empty("1"), empty("2"), page(["v1"], next: "3"), empty("4"), empty("5"), empty("6"), empty("7"), page(["v2"], next: nil)])
        let list = PagedList<FeedVideo>(session: session) { cursor in
            try await LoadVideoPageUseCase(videos: videoLists)(.myLikes, cursor: cursor).asPage
        }
        await list.loadFirst()
        #expect(list.items.map(\.id) == ["v1"])
        #expect(list.nextCursor == "3")
        // 4 pages vides d'affilée : la liste s'arrête après 3 sauts, et reprendra au prochain défilement.
        await list.loadMore()
        #expect(list.items.map(\.id) == ["v1"])
        #expect(list.nextCursor == "7")
        await list.loadMore()
        #expect(list.items.map(\.id) == ["v1", "v2"])
        #expect(videoLists.requests.count == 8)
    }

    @Test("lecteur d'une grille : ouvert sur la vidéo touchée, s'arrête à la fin, vidéo supprimée retirée")
    func listPlayer() async {
        let session = await makeSession()
        let playback = FakePlayback()
        let viewModel = FeedViewModel(
            loadPage: LoadVideoListUseCase(videos: videoLists, list: .myLikes),
            recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
            playback: playback,
            session: session,
            analytics: makeAnalytics(),
            mode: .list(page(["v1", "v2", "v3"], next: nil), startIndex: 1)
        )
        await viewModel.start()
        #expect(viewModel.currentVideo?.id == "v2")
        #expect(playback.played == ["v2"])
        await viewModel.loadMore()
        #expect(videoLists.requests.isEmpty)

        viewModel.remove(videoIDs: ["v2"])
        #expect(viewModel.entries.map(\.video.id) == ["v1", "v3"])
        #expect(viewModel.currentVideo?.id == "v3")
    }

    @Test("compte bloqué : ses vidéos quittent le lecteur, la suivante devient courante")
    func listPlayerBlockedAuthor() async {
        let session = await makeSession()
        let viewModel = FeedViewModel(
            loadPage: LoadVideoListUseCase(videos: videoLists, list: .myLikes),
            recordView: RecordViewUseCase(history: FakeViewHistoryRepository()),
            playback: FakePlayback(),
            session: session,
            analytics: makeAnalytics(),
            mode: .list(
                FeedPage(videos: [.sample("v1", author: "carol"), .sample("v2"), .sample("v3"), .sample("v4", author: "carol")], nextCursor: nil),
                startIndex: 1)
        )
        await viewModel.start()
        #expect(viewModel.currentVideo?.id == "v2")
        viewModel.remove(authorIDs: ["bob-id"])
        #expect(viewModel.entries.map(\.video.id) == ["v1", "v4"])
        #expect(viewModel.currentVideo?.id == "v4")
    }

    @Test("supprimer sa vidéo : signalée aux écrans ; celle d'un autre : ignorée")
    func deleteVideo() async {
        let session = await makeSession()
        let interactions = makeInteractions(session)
        let sample = FeedVideo.sample("mine")
        let mine = FeedVideo(
            id: "mine", description: nil, hlsURL: sample.hlsURL, thumbnailURL: sample.thumbnailURL, createdAt: sample.createdAt,
            stats: sample.stats, author: .alice, viewer: nil)
        #expect(await interactions.delete(mine) == nil)
        #expect(await interactions.delete(.sample("theirs", author: "bob")) == nil)
        #expect(interactions.deletedVideoIDs == ["mine"])
        #expect(publishingRepository.deleted == ["mine"])
    }
}

@MainActor
@Suite("Profil : compteurs en direct (ADR-045)")
struct OwnProfileSyncTests {
    @Test("événement profileCountersChanged décodé")
    func decoding() {
        let update = RealtimeEventDecoder().decode(#"{"event":"profileCountersChanged","data":{"followersCount":12,"followingCount":4}}"#)
        #expect(update == .profileCountersChanged(followers: 12, following: 4))
    }

    @Test("compteurs reçus : son profil à jour dans la session ; sans effet en invité")
    func countersChanged() async {
        let profiles = FakeProfileRepository()
        let session = makeSession(auth: FakeAuthRepository(hasSession: true), profiles: profiles)
        await session.restore()
        let sync = OwnProfileSync(session: session, getMyProfile: GetMyProfileUseCase(profiles: profiles))

        sync.countersChanged(followers: 10, following: 2)
        #expect(session.profile?.followersCount == 10)
        #expect(session.profile?.followingCount == 2)
        #expect(session.profile?.username == "alice")

        await session.signOut()
        sync.countersChanged(followers: 99, following: 99)
        #expect(session.profile == nil)
    }

    @Test("reconnexion : profil relu par l'API ; échec réseau sans effet")
    func refresh() async {
        let profiles = FakeProfileRepository()
        let session = makeSession(auth: FakeAuthRepository(hasSession: true), profiles: profiles)
        await session.restore()
        let sync = OwnProfileSync(session: session, getMyProfile: GetMyProfileUseCase(profiles: profiles))

        profiles.result.withLock { $0 = .success(UserProfile.alice.with(followersCount: 7, followingCount: 5)) }
        await sync.refresh()
        #expect(session.profile?.followersCount == 7)
        #expect(session.profile?.followingCount == 5)

        profiles.result.withLock { $0 = .failure(.network) }
        await sync.refresh()
        #expect(session.profile?.followersCount == 7)
    }
}
