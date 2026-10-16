import Foundation
import Testing

@testable import TikTokClone

@Suite("Profil : règles et cas d'usage")
struct ProfileUseCasesTests {
    let alice = UserProfile.alice  // pseudo « alice », nom « Alice », bio « Bonjour »

    @Test("changements : seuls les champs modifiés, nettoyés ; bio vide = effacée")
    func changes() throws {
        #expect(try ProfileRules.changes(from: alice, username: "alice", displayName: " Alice ", bio: "Bonjour ").get().isEmpty)
        #expect(
            try ProfileRules.changes(from: alice, username: "alice_2", displayName: "Alice", bio: "Bonjour").get()
                == ProfileChanges(username: "alice_2", displayName: nil, bio: nil))
        #expect(
            try ProfileRules.changes(from: alice, username: "alice", displayName: "Alice M.", bio: "  ").get()
                == ProfileChanges(username: nil, displayName: "Alice M.", bio: ""))
    }

    @Test("changements refusés : pseudo invalide ou réservé, nom vide, bio trop longue")
    func invalidChanges() {
        #expect(throws: AppError.self) { try ProfileRules.changes(from: alice, username: "Alice", displayName: "Alice", bio: "").get() }
        #expect(throws: AppError.rejected("Ce pseudo n’est pas disponible.")) {
            try ProfileRules.changes(from: alice, username: "me", displayName: "Alice", bio: "").get()
        }
        #expect(throws: AppError.rejected("Nom : 1 à 50 caractères.")) {
            try ProfileRules.changes(from: alice, username: "alice", displayName: "  ", bio: "").get()
        }
        #expect(throws: AppError.rejected("Bio : 80 caractères au plus.")) {
            try ProfileRules.changes(from: alice, username: "alice", displayName: "Alice", bio: String(repeating: "a", count: 81)).get()
        }
    }

    @Test("bouton d'abonnement : Suivre, Suivre en retour, Abonné(e), Ami(e)s")
    func followStatus() {
        #expect(FollowStatus(following: false, followedBy: false).title == "Suivre")
        #expect(FollowStatus(following: false, followedBy: true).title == "Suivre en retour")
        #expect(FollowStatus(following: true, followedBy: false).title == "Abonné(e)")
        #expect(FollowStatus(following: true, followedBy: true) == .friends)
        #expect(FollowStatus.friends.isFollowing)
        #expect(!FollowStatus.followBack.isFollowing)
    }

    @Test("grilles : favoris et likes sur son seul profil")
    func grids() {
        #expect(ProfileGrid.available(isOwn: true) == [.videos, .privateVideos, .reposts, .favorites, .likes])
        #expect(ProfileGrid.available(isOwn: false) == [.videos, .reposts])
        #expect(VideoList(.likes, username: "alice") == .myLikes)
        #expect(VideoList(.reposts, username: "bob") == .reposts(username: "bob"))
    }

    @Test("modification : rien n'est envoyé sans changement ; sinon les seuls champs changés")
    func update() async throws {
        let profiles = FakeProfileRepository()
        let update = UpdateProfileUseCase(profiles: profiles)
        #expect(try await update(alice, username: "alice", displayName: "Alice", bio: "Bonjour") == alice)
        #expect(profiles.updates.isEmpty)
        let updated = try await update(alice, username: "alice", displayName: "Alice", bio: "")
        #expect(profiles.updates == [ProfileChanges(username: nil, displayName: nil, bio: "")])
        #expect(updated.bio == nil)
    }

    @Test("photo : URL signée, envoi au stockage, puis installation ; plus de 5 Mo refusé sans appel")
    func avatar() async throws {
        let profiles = FakeProfileRepository()
        let transport = FakeAvatarTransport()
        let change = ChangeAvatarUseCase(profiles: profiles, transport: transport)
        let profile = try await change(Data(count: 1000), type: .jpeg)
        #expect(profiles.calls == ["avatarUpload-image/jpeg-1000", "setAvatar-avatar-1"])
        #expect(transport.count == 1)
        #expect(profile.avatarURL?.absoluteString == "http://cdn.test/avatars/avatar-1")

        await #expect(throws: AppError.rejected("La photo dépasse 5 Mo.")) {
            try await change(Data(count: ProfileRules.maxAvatarSize + 1), type: .jpeg)
        }
        #expect(transport.count == 1)
    }

    @Test("suppression du compte : compte supprimé, puis session oubliée sur l'appareil")
    func deleteAccount() async throws {
        let profiles = FakeProfileRepository()
        let auth = FakeAuthRepository(hasSession: true)
        try await DeleteAccountUseCase(profiles: profiles, auth: auth)()
        #expect(profiles.calls == ["deleteAccount"])
        #expect(!auth.hasStoredSession())

        let failing = FakeProfileRepository()
        failing.fail(with: .network)
        let kept = FakeAuthRepository(hasSession: true)
        await #expect(throws: AppError.network) { try await DeleteAccountUseCase(profiles: failing, auth: kept)() }
        #expect(kept.hasStoredSession())
    }

    @Test("envois d'un compte supprimé oubliés, ceux des autres gardés")
    func discardUploads() throws {
        let store = InMemoryUploadStore()
        try store.save(.sample(id: "a"))
        try store.save(.sample(id: "b", userID: "bob-id"))
        DiscardUploadsUseCase(store: store)(userID: UserProfile.alice.id)
        #expect(store.uploads.map(\.id) == ["b"])
    }
}
