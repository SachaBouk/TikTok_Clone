import Foundation
import Testing

@testable import TikTokClone

private let me = UserProfile.alice.id
private let carla = UserSummary(id: "carla-id", username: "carla", displayName: "Carla", avatarURL: nil)

@MainActor
private func makeMessaging(
    _ repository: FakeMessagingRepository, channel: FakeRealtimeChannel = FakeRealtimeChannel(), typingDisplay: Duration = .seconds(5)
) async -> (MessagingModel, SessionStore) {
    let session = makeSession(auth: FakeAuthRepository(hasSession: true))
    await session.restore()
    let model = MessagingModel(
        loadConversations: LoadConversationsUseCase(messaging: repository),
        loadRequests: LoadMessageRequestsUseCase(messaging: repository),
        loadConversation: LoadConversationUseCase(messaging: repository),
        countUnread: CountUnreadMessagesUseCase(messaging: repository),
        answerRequest: AnswerMessageRequestUseCase(messaging: repository),
        deleteConversation: DeleteConversationUseCase(messaging: repository),
        sendTyping: SendTypingUseCase(channel: channel),
        session: session,
        typingDisplay: typingDisplay
    )
    return (model, session)
}

@MainActor
@Suite("Messagerie : modèle partagé")
struct MessagingModelTests {
    let repository = FakeMessagingRepository()
    let badges = MessagingBadges(unreadConversations: 1, pendingRequests: 1)

    init() {
        repository.add(.sample("c1", lastMessage: .sample("m10", in: "c1")), messages: [.sample("m10", in: "c1")])
        repository.add(
            .sample("c2", with: carla, lastMessage: .sample("m11", in: "c2", from: carla.id)), messages: [.sample("m11", in: "c2", from: carla.id)])
    }

    @Test("connexion : badges relus ; les listes ne sont chargées qu'à l'affichage")
    func refresh() async {
        repository.setBadges(badges)
        let (model, _) = await makeMessaging(repository)
        await model.refresh()
        #expect(model.badges == badges)
        #expect(model.badgeCount == 2)
        #expect(model.inbox.state == .idle)
    }

    @Test("nouveau message : badges de l'événement, conversation en tête, pastille non lue")
    func messageMovesToTop() async {
        let (model, _) = await makeMessaging(repository)
        await model.inbox.loadFirst()
        #expect(model.inbox.items.map(\.id) == ["c2", "c1"])
        model.handle(.messageCreated(.sample("m12", in: "c1"), badges))
        #expect(model.inbox.items.map(\.id) == ["c1", "c2"])
        #expect(model.inbox.items.first?.unreadCount == 1)
        #expect(model.inbox.items.first?.lastMessage?.id == "m12")
        #expect(model.badges == badges)
    }

    @Test("nouvelle conversation ou demande : relue par l'API et placée dans la bonne liste")
    func newConversation() async {
        let (model, _) = await makeMessaging(repository)
        await model.inbox.loadFirst()
        await model.requests.loadFirst()
        let dan = UserSummary(id: "dan-id", username: "dan", displayName: "Dan", avatarURL: nil)
        repository.add(.sample("c3", with: dan, status: .requestReceived, lastMessage: .sample("m13", in: "c3", from: dan.id)))
        model.handle(.messageCreated(.sample("m13", in: "c3", from: dan.id), badges))
        #expect(await eventually { model.requests.items.map(\.id) == ["c3"] })
        #expect(!model.inbox.items.contains { $0.id == "c3" })

        // Demande acceptée (sur un autre appareil) : elle passe dans la boîte de réception.
        repository.update("c3") { $0.status = .direct }
        model.handle(.conversationAccepted(conversationID: "c3", badges))
        #expect(await eventually { model.inbox.items.first?.id == "c3" && model.requests.items.isEmpty })
    }

    @Test("« Vu » et lecture sur un autre appareil ; suppression et message retiré")
    func readAndDelete() async {
        let (model, _) = await makeMessaging(repository)
        await model.inbox.loadFirst()
        model.handle(.messageCreated(.sample("m12", in: "c2", from: carla.id), badges))
        model.handle(.conversationRead(conversationID: "c2", readerID: me, lastReadMessageID: "m12", .zero))
        #expect(model.inbox.items.first { $0.id == "c2" }?.unreadCount == 0)
        model.handle(.conversationRead(conversationID: "c1", readerID: UserSummary.bob.id, lastReadMessageID: "m10", .zero))
        #expect(model.inbox.items.first { $0.id == "c1" }?.participantLastReadMessageID == "m10")

        // Le dernier message retiré : la ligne est relue (ici, plus aucun message : elle disparaît).
        repository.update("c1") { $0.lastMessage = nil }
        model.handle(.messageDeleted(conversationID: "c1", messageID: "m10", .zero))
        #expect(await eventually { !model.inbox.items.contains { $0.id == "c1" } })

        model.handle(.conversationDeleted(conversationID: "c2", .zero))
        #expect(model.inbox.items.isEmpty)
    }

    @Test("« en train d'écrire » : affiché, effacé après le délai ou à l'arrivée du message ; le sien ignoré")
    func typing() async {
        let (model, _) = await makeMessaging(repository, typingDisplay: .milliseconds(50))
        model.handle(.typing(conversationID: "c1", userID: me))
        #expect(!model.isTyping(in: "c1"))
        model.handle(.typing(conversationID: "c1", userID: UserSummary.bob.id))
        #expect(model.isTyping(in: "c1"))
        #expect(await eventually { !model.isTyping(in: "c1") })

        model.handle(.typing(conversationID: "c2", userID: carla.id))
        model.handle(.messageCreated(.sample("m12", in: "c2", from: carla.id), badges))
        #expect(!model.isTyping(in: "c2"))
    }

    @Test("glisser : supprimer une conversation, refuser une demande ; déconnexion : tout est oublié")
    func swipeAndReset() async {
        repository.add(.sample("c3", status: .requestReceived, lastMessage: .sample("m13", in: "c3")))
        let (model, _) = await makeMessaging(repository)
        await model.inbox.loadFirst()
        await model.requests.loadFirst()
        #expect(await model.delete(model.inbox.items[0]) == nil)
        #expect(await model.decline(model.requests.items[0]) == nil)
        #expect(repository.calls.contains("deleteConversation"))
        #expect(repository.calls.contains("decline"))
        #expect(model.requests.items.isEmpty)
        #expect(model.inbox.items.count == 1)

        model.handle(.messageCreated(.sample("m14", in: "c1"), badges))
        model.reset()
        #expect(model.badges == .zero)
        #expect(model.inbox.state == .idle)
    }
}

@MainActor
@Suite("Messagerie : conversation")
struct ConversationViewModelTests {
    let repository = FakeMessagingRepository()
    let channel = FakeRealtimeChannel()
    let clock = TestClock()

    init() {
        let messages: [DirectMessage] = [.sample("m10", from: me), .sample("m11"), .sample("m12"), .sample("m13")]
        repository.add(.sample("c1", lastMessage: messages.last, unreadCount: 2), messages: messages)
    }

    func makeViewModel(_ route: ConversationRoute = ConversationRoute(username: "bob")) async -> (ConversationViewModel, MessagingModel) {
        let (messaging, session) = await makeMessaging(repository, channel: channel)
        return (makeConversationViewModel(route, messaging: messaging, session: session), messaging)
    }

    // Un autre écran de conversation sur le même modèle partagé (conversation fermée puis rouverte).
    func makeConversationViewModel(
        _ route: ConversationRoute = ConversationRoute(username: "bob"), messaging: MessagingModel, session: SessionStore
    ) -> ConversationViewModel {
        ConversationViewModel(
            route: route,
            loadConversation: LoadConversationUseCase(messaging: repository),
            loadMessages: LoadMessagesUseCase(messaging: repository),
            sendMessage: SendMessageUseCase(messaging: repository),
            markRead: MarkConversationReadUseCase(messaging: repository),
            answerRequest: AnswerMessageRequestUseCase(messaging: repository),
            deleteConversation: DeleteConversationUseCase(messaging: repository),
            deleteMessage: DeleteMessageUseCase(messaging: repository),
            messaging: messaging,
            session: session,
            analytics: makeAnalytics(),
            now: { [clock] in clock.now }
        )
    }

    @Test("ouverture par pseudo : messages du plus ancien au plus récent, plus anciens chargés en remontant")
    func loadAndOlder() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        #expect(repository.calls.first == "open:bob")
        #expect(viewModel.messages.map(\.id) == ["m12", "m13"])
        #expect(viewModel.hasOlderMessages)
        #expect(await viewModel.loadOlder() == "m12")
        #expect(viewModel.messages.map(\.id) == ["m10", "m11", "m12", "m13"])
        #expect(!viewModel.hasOlderMessages)
    }

    @Test("marqué lu seulement une fois affiché, jusqu'au message le plus récent ; puis à chaque message reçu")
    func markRead() async {
        repository.setBadges(MessagingBadges(unreadConversations: 1, pendingRequests: 0))
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(repository.markedUpTo.isEmpty)
        viewModel.setVisible(true)
        #expect(await eventually { repository.markedUpTo == ["m13"] })
        #expect(await eventually { messaging.badges.unreadConversations == 0 })

        messaging.handle(.messageCreated(.sample("m14"), .zero))
        #expect(viewModel.messages.last?.id == "m14")
        #expect(await eventually { repository.markedUpTo == ["m13", "m14"] })

        // Écran quitté : plus rien n'est marqué lu.
        viewModel.setVisible(false)
        messaging.handle(.messageCreated(.sample("m15"), .zero))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(repository.markedUpTo == ["m13", "m14"])
    }

    @Test("envoi : texte nettoyé, ajouté au fil, champ vidé ; « Vu » quand l'autre l'a lu")
    func send() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        viewModel.draft = "  Coucou  "
        await viewModel.send()
        #expect(repository.sentContents == ["Coucou"])
        // Identifiant d'envoi joint (ADR-044).
        #expect(repository.sentClientMessageIDs.allSatisfy { $0 != nil })
        #expect(viewModel.messages.last?.content == "Coucou")
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.draft.isEmpty)
        let sent = viewModel.messages.last!.id
        #expect(viewModel.seen == nil)
        viewModel.read(by: UserSummary.bob.id, upTo: sent)
        #expect(viewModel.seen?.messageID == sent)
        #expect(viewModel.seen?.label == "Vu")
    }

    @Test("limite d'envoi : message « Non envoyé », envoi et renvoi bloqués pendant le délai de l'API")
    func rateLimited() async throws {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        repository.failSending(with: .rateLimited(retryAfter: 30))
        viewModel.draft = "Encore"
        await viewModel.send()
        let failed = try #require(viewModel.pending.first)
        #expect(failed.state == .failed)
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.secondsBeforeSending(at: clock.now) == 30)
        viewModel.draft = "Autre"
        #expect(!viewModel.canSend(at: clock.now))
        #expect(viewModel.canSend(at: clock.now.addingTimeInterval(30)))
        #expect(viewModel.errorMessage == nil)

        // Réessayer trop tôt : le délai est rappelé, rien n'est envoyé.
        await viewModel.retry(failed)
        #expect(viewModel.errorMessage == "Trop de messages envoyés. Réessaie dans 30 s.")
        #expect(repository.sentContents == ["Encore"])
        viewModel.errorMessage = nil

        clock.advance(by: 30)
        repository.failSending(with: nil)
        await viewModel.retry(failed)
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.messages.last?.content == "Encore")
        #expect(repository.sentClientMessageIDs == [failed.id, failed.id])
    }

    @Test("coupure : « Non envoyé » sans alerte, gardé en quittant la conversation, réessayé avec le même identifiant")
    func networkFailureAndRetry() async throws {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        repository.failSending(with: .network)
        viewModel.draft = "Tu es là ?"
        await viewModel.send()
        let failed = try #require(viewModel.pending.first)
        #expect(failed.state == .failed)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.draft.isEmpty)

        // Conversation fermée puis rouverte : le message attend toujours (gardé par MessagingModel).
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let reopened = makeConversationViewModel(messaging: messaging, session: session)
        await reopened.load()
        #expect(reopened.pending == [failed])

        repository.failSending(with: nil)
        await reopened.retry(failed)
        #expect(reopened.pending.isEmpty)
        #expect(reopened.messages.last?.content == "Tu es là ?")
        #expect(repository.sentClientMessageIDs == [failed.id, failed.id])
    }

    @Test("réponse perdue : le renvoi rend le message déjà enregistré, sans doublon")
    func lostResponseRetry() async throws {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        repository.losesResponse(true)
        viewModel.draft = "Une seule fois"
        await viewModel.send()
        let failed = try #require(viewModel.pending.first)
        #expect(failed.state == .failed)

        repository.losesResponse(false)
        await viewModel.retry(failed)
        #expect(repository.messages(of: "c1").count { $0.content == "Une seule fois" } == 1)
        #expect(viewModel.messages.count { $0.content == "Une seule fois" } == 1)
        #expect(viewModel.pending.isEmpty)
    }

    @Test("écho temps réel d'un envoi dont la réponse s'est perdue : la bulle « Non envoyé » disparaît")
    func echoClearsFailed() async throws {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        repository.failSending(with: .network)
        viewModel.draft = "Arrivé quand même"
        await viewModel.send()
        let failed = try #require(viewModel.pending.first)

        var echo = DirectMessage.sample("m30", from: me, content: "Arrivé quand même")
        echo.clientMessageID = failed.id
        messaging.handle(.messageCreated(echo, .zero))
        #expect(viewModel.pending.isEmpty)
        #expect(viewModel.messages.last?.id == "m30")
    }

    @Test("supprimer un message non envoyé ; ses messages non envoyés partent avec la conversation, et à la déconnexion")
    func discardFailed() async throws {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        repository.failSending(with: .network)
        viewModel.draft = "Un"
        await viewModel.send()
        viewModel.draft = "Deux"
        await viewModel.send()
        #expect(viewModel.pending.map(\.content) == ["Un", "Deux"])
        viewModel.discard(viewModel.pending[0])
        #expect(viewModel.pending.map(\.content) == ["Deux"])

        messaging.removed("c1")
        #expect(viewModel.pending.isEmpty)
        viewModel.draft = "Trois"
        await viewModel.send()
        messaging.reset()
        #expect(messaging.outgoing.isEmpty)
    }

    @Test("envoi refusé (blocage) : message affiché, conversation relue")
    func blocked() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        repository.failSending(with: .rejected("Impossible d’écrire à ce compte"))
        repository.update("c1") { $0.canSend = false }
        viewModel.draft = "Salut"
        await viewModel.send()
        #expect(viewModel.errorMessage == "Impossible d’écrire à ce compte")
        // « Non envoyé », sans « Réessayer » (la conversation ne permet plus d'écrire).
        #expect(viewModel.pending.map(\.state) == [.failed])
        #expect(!viewModel.canRetry(at: clock.now))
        #expect(viewModel.conversation?.canSend == false)
        #expect(viewModel.conversation?.composerNotice == "Tu ne peux pas écrire à ce compte.")
    }

    @Test("« en train d'écrire » : au plus toutes les 3 s pendant la saisie, pas dans une demande")
    func typing() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        viewModel.draft = "S"
        viewModel.draft = "Sa"
        clock.advance(by: 3)
        viewModel.draft = "Sal"
        #expect(await eventually { channel.typingSent == ["c1", "c1"] })

        repository.update("c1") {
            $0.status = .requestSent
            $0.remainingRequestMessages = 3
        }
        await viewModel.load()
        clock.advance(by: 3)
        viewModel.draft = "Salu"
        try? await Task.sleep(for: .milliseconds(20))
        #expect(channel.typingSent.count == 2)
    }

    @Test("son message renvoyé par le temps réel pendant l'envoi : pas de doublon")
    func echoWhileSending() async {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        let echo = DirectMessage.sample("m20", from: me, content: "Hello")
        messaging.handle(.messageCreated(echo, .zero))
        #expect(viewModel.messages.filter { $0.id == "m20" }.count == 1)
        messaging.handle(.messageCreated(echo, .zero))
        #expect(viewModel.messages.filter { $0.id == "m20" }.count == 1)
        messaging.handle(.messageDeleted(conversationID: "c1", messageID: "m20", .zero))
        #expect(!viewModel.messages.contains { $0.id == "m20" })
    }

    @Test("demande reçue : accepter la rend libre ; refuser ferme l'écran")
    func request() async {
        repository.update("c1") { $0.status = .requestReceived }
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        #expect(viewModel.isRequestReceived)
        await viewModel.accept()
        #expect(viewModel.conversation?.status == .direct)

        repository.update("c1") { $0.status = .requestReceived }
        await viewModel.load()
        await viewModel.decline()
        #expect(viewModel.isClosed)
        #expect(repository.calls.contains("decline"))
    }

    @Test("retrait de son message ; conversation supprimée ailleurs : l'écran se ferme")
    func retractAndDeleted() async {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        viewModel.draft = "Oups"
        await viewModel.send()
        let sent = viewModel.messages.last!
        await viewModel.retract(sent)
        #expect(!viewModel.messages.contains(sent))
        #expect(repository.calls.contains("deleteMessage:\(sent.id)"))

        messaging.handle(.conversationDeleted(conversationID: "c1", .zero))
        #expect(viewModel.isClosed)
    }
}

@MainActor
@Suite("Messagerie : envoyer une vidéo")
struct SendVideoTests {
    @Test("destinataires : conversations récentes puis abonnements sans doublon ; envoi compté comme un partage")
    func send() async {
        let repository = FakeMessagingRepository()
        repository.add(.sample("c1", lastMessage: .sample("m10")))
        let (messaging, session) = await makeMessaging(repository)
        let relationships = FakeRelationshipRepository()
        relationships.state.withLock {
            $0.follows[.following] = [
                FollowEntry(user: .bob, followedAt: .now, viewer: nil),
                FollowEntry(user: carla, followedAt: .now, viewer: nil),
            ]
        }
        let interactionRepository = FakeInteractionRepository()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: makeAnalytics()
        )
        let video = FeedVideo.sample("v1")
        let viewModel = SendVideoViewModel(
            video: video,
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: relationships),
            share: ShareVideoByMessageUseCase(messaging: repository),
            interactions: interactions,
            session: session
        )
        await viewModel.load()
        #expect(viewModel.recent.map(\.label) == ["@bob"])
        #expect(viewModel.others.map(\.label) == ["@carla"])

        await viewModel.send(to: viewModel.others[0])
        #expect(viewModel.deliveries["carla-id"] == .sent)
        #expect(repository.sentVideoIDs == ["v1"])
        #expect(interactions.display(video).stats.shares == video.stats.shares + 1)
    }

    // Bob a une conversation (et suit en retour : ami) ; abonnements : Bob, Éloïse, zoé, 42club.
    private func makeSelection(_ repository: FakeMessagingRepository) async -> (SendVideoViewModel, VideoInteractionsModel, FeedVideo) {
        repository.add(.sample("c1", lastMessage: .sample("m10")))
        let (messaging, session) = await makeMessaging(repository)
        let relationships = FakeRelationshipRepository()
        let user = { (name: String, display: String) in UserSummary(id: "\(name)-id", username: name, displayName: display, avatarURL: nil) }
        relationships.state.withLock {
            $0.follows[.following] = [
                FollowEntry(user: .bob, followedAt: .now, viewer: FollowViewer(following: true, followedBy: true)),
                FollowEntry(user: user("eloise", "Éloïse"), followedAt: .now, viewer: FollowViewer(following: true, followedBy: false)),
                FollowEntry(user: user("zoe", "zoé"), followedAt: .now, viewer: FollowViewer(following: true, followedBy: true)),
                FollowEntry(user: user("club42", "42club"), followedAt: .now, viewer: FollowViewer(following: true, followedBy: false)),
            ]
        }
        let interactionRepository = FakeInteractionRepository()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: makeAnalytics()
        )
        let video = FeedVideo.sample("v1")
        let viewModel = SendVideoViewModel(
            video: video,
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: relationships),
            share: ShareVideoByMessageUseCase(messaging: repository),
            interactions: interactions,
            session: session
        )
        await viewModel.load()
        return (viewModel, interactions, video)
    }

    @Test("destinataires choisis puis « Envoyer » : la vidéo et le message partent ensemble, à chacun")
    func sendSelected() async {
        let repository = FakeMessagingRepository()
        let (viewModel, interactions, video) = await makeSelection(repository)
        let eloise = viewModel.others.first { $0.username == "eloise" }!
        viewModel.toggle(viewModel.recent[0])
        viewModel.toggle(eloise)
        #expect(repository.sentVideoIDs.isEmpty)
        #expect(viewModel.selected.map(\.label) == ["@bob", "@eloise"])
        viewModel.toggle(eloise)
        viewModel.toggle(eloise)
        viewModel.message = "  Regarde ça "
        viewModel.appendEmoji("😂")

        #expect(await viewModel.sendSelected())
        #expect(repository.sentVideoIDs == ["v1", "v1"])
        #expect(repository.sentContents == ["Regarde ça 😂", "Regarde ça 😂"])
        #expect(repository.sentClientMessageIDs.allSatisfy { $0 != nil })
        #expect(viewModel.selected.isEmpty)
        #expect(viewModel.message.isEmpty)
        #expect(viewModel.deliveries["eloise-id"] == .sent)
        #expect(interactions.display(video).stats.shares == video.stats.shares + 2)
    }

    @Test("sans message : la vidéo seule ; un échec garde le destinataire choisi, et le même identifiant au nouvel essai")
    func sendSelectedFailure() async {
        let repository = FakeMessagingRepository()
        let (viewModel, _, _) = await makeSelection(repository)
        viewModel.toggle(viewModel.recent[0])
        #expect(viewModel.canSendSelected)
        repository.failSending(with: .network)
        #expect(await viewModel.sendSelected() == false)
        #expect(viewModel.selected.map(\.label) == ["@bob"])
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.deliveries["bob-id"] == nil)

        repository.failSending(with: nil)
        #expect(await viewModel.sendSelected())
        #expect(repository.sentContents == [nil, nil])
        let ids = repository.sentClientMessageIDs
        #expect(ids.count == 2 && ids[0] != nil && ids[0] == ids[1])
    }

    @Test("liste complète : chats récents, amis, puis suivis de A à Z ; recherche sans casse ni accents, sans doublon")
    func sectionsAndSearch() async {
        let repository = FakeMessagingRepository()
        let (viewModel, _, _) = await makeSelection(repository)
        await viewModel.loadAllFollowing()
        #expect(viewModel.hasLoadedAllFollowing)
        let sections = viewModel.sections
        #expect(sections.map(\.kind) == [.recent, .friends, .letter("B"), .letter("E"), .letter("Z"), .letter("#")])
        #expect(sections[1].recipients.map(\.label) == ["@bob", "@zoe"])
        #expect(viewModel.isFriend(viewModel.recent[0]))

        viewModel.query = "ELOISE"
        #expect(viewModel.searchResults.map(\.label) == ["@eloise"])
        viewModel.query = "@bo"
        #expect(viewModel.searchResults.map(\.label) == ["@bob"])
        viewModel.query = "  "
        #expect(!viewModel.isSearching)
    }
}

// Horloge des tests : avancée à la main.
@MainActor
final class TestClock {
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
