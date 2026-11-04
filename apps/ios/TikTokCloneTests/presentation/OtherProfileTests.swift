import Foundation
import Testing

@testable import TikTokClone

// Profil d'un autre compte façon TikTok (ADR-069) : comptes suggérés liés au profil, profil partagé par message.
@MainActor
@Suite("Profil d'un autre compte")
struct OtherProfileTests {
    private func suggestion(_ user: UserSummary, followsYou: Bool = false) -> AccountSuggestion {
        AccountSuggestion(user: user, followersCount: 3, followsYou: followsYou, followedBy: [], followedByCount: 0)
    }

    @Test("comptes suggérés d'un profil : lus une fois, sans les écartés ni les bloqués")
    func profileSuggestions() async {
        let session = await makeSession()
        let repository = FakeSuggestionRepository()
        repository.byProfile.withLock { $0["carol"] = [suggestion(.alice), suggestion(.bob, followsYou: true)] }
        let model = ProfileSuggestionsModel(username: "carol", load: LoadProfileSuggestionsUseCase(suggestions: repository), session: session)
        #expect(model.state == .idle)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(model.state == .loaded)
        #expect(repository.requestedProfiles.withLock { $0 } == ["carol"])
        #expect(model.visible(dismissed: DismissedSuggestions(), blocked: []).map(\.id) == [UserSummary.alice.id, UserSummary.bob.id])
        #expect(model.visible(dismissed: DismissedSuggestions([UserSummary.alice.id]), blocked: []).map(\.id) == [UserSummary.bob.id])
        #expect(model.visible(dismissed: DismissedSuggestions(), blocked: [UserSummary.bob.id]).map(\.id) == [UserSummary.alice.id])
    }

    @Test("dépliage : les comptes sont attendus avant d'ouvrir la rangée (à sa hauteur finale), une seule lecture")
    func prepareBeforeOpening() async {
        let session = await makeSession()
        let repository = FakeSuggestionRepository()
        repository.byProfile.withLock { $0["carol"] = [suggestion(.alice)] }
        let model = ProfileSuggestionsModel(username: "carol", load: LoadProfileSuggestionsUseCase(suggestions: repository), session: session)
        await model.prepare(waitingAtMost: .seconds(2))
        #expect(model.state == .loaded)
        await model.prepare(waitingAtMost: .seconds(2))
        #expect(repository.requestedProfiles.withLock { $0 } == ["carol"])
    }

    @Test("feuille « Envoyer à » d'un profil : la carte du profil part avec le message, à chaque destinataire")
    func shareProfile() async {
        let session = await makeSession()
        let messagingRepository = FakeMessagingRepository()
        let messaging = MessagingModel(
            loadConversations: LoadConversationsUseCase(messaging: messagingRepository),
            loadRequests: LoadMessageRequestsUseCase(messaging: messagingRepository),
            loadConversation: LoadConversationUseCase(messaging: messagingRepository),
            countUnread: CountUnreadMessagesUseCase(messaging: messagingRepository),
            answerRequest: AnswerMessageRequestUseCase(messaging: messagingRepository),
            deleteConversation: DeleteConversationUseCase(messaging: messagingRepository),
            sendTyping: SendTypingUseCase(channel: FakeRealtimeChannel()),
            session: session
        )
        let interactionRepository = FakeInteractionRepository()
        let carol = UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil)
        let viewModel = SendVideoViewModel(
            item: .profile(carol),
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: FakeRelationshipRepository()),
            share: ShareVideoByMessageUseCase(messaging: messagingRepository),
            shareLive: nil,
            shareProfile: ShareProfileByMessageUseCase(messaging: messagingRepository),
            interactions: VideoInteractionsModel(
                setReaction: SetReactionUseCase(interactions: interactionRepository),
                setFollow: SetFollowUseCase(interactions: interactionRepository),
                recordShare: ShareVideoUseCase(interactions: interactionRepository),
                deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
                session: session,
                analytics: makeAnalytics()
            ),
            session: session
        )
        viewModel.toggle(.init(user: .bob))
        viewModel.message = "Regarde"
        #expect(await viewModel.sendSelected())
        #expect(messagingRepository.sharedProfiles.withLock { $0.map(\.userID) } == ["carol-id"])
        #expect(messagingRepository.sentContents == ["Regarde"])
        // Pas de vidéo partagée : aucun partage compté.
        #expect(messagingRepository.sentVideoIDs == [nil])
    }

    @Test("aperçu d'un profil partagé dans la boîte de réception")
    func preview() {
        let message = DirectMessage(
            id: "m1", conversationID: "c1", senderID: "bob-id", content: "", sharedVideo: nil, createdAt: .now,
            profile: SharedProfile(id: "carol-id", user: nil))
        #expect(message.preview(ownID: "alice-id") == "Profil partagé")
        #expect(message.preview(ownID: "bob-id") == "Toi : Profil partagé")
    }
}
