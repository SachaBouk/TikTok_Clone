import Foundation
import Testing

@testable import TikTokClone

// Chats de groupe (ADR-059) : règles, choix d'amis, conversation de groupe, modèle partagé, partage d'une vidéo.

private let ines = UserSummary(id: "ines-id", username: "ines", displayName: "Inès", avatarURL: nil)
private let nathan = UserSummary(id: "nathan-id", username: "nathan", displayName: "Nathan", avatarURL: nil)
private let lea = UserSummary(id: "lea-id", username: "lea", displayName: "Léa", avatarURL: nil)

@MainActor
private func makeMessaging(_ repository: FakeMessagingRepository, channel: FakeRealtimeChannel = FakeRealtimeChannel()) async -> (
    MessagingModel, SessionStore
) {
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
        session: session
    )
    return (model, session)
}

private func groupMessage(_ id: String, from sender: UserSummary, content: String = "Salut", event: GroupEvent? = nil) -> DirectMessage {
    var message = DirectMessage.sample(id, in: "g1", from: sender.id, content: content)
    message.sender = sender
    message.event = event
    return message
}

@Suite("Chats de groupe : règles")
struct GroupRulesTests {
    @Test("titre : nom du groupe, sinon les noms des autres membres")
    func title() {
        #expect(GroupRules.names(["Inès"]) == "Inès")
        #expect(GroupRules.names(["Inès", "Nathan"]) == "Inès et Nathan")
        #expect(GroupRules.names(["Inès", "Nathan", "Léa"]) == "Inès, Nathan et Léa")
        #expect(GroupRules.names(["Inès", "Nathan", "Léa", "Bob", "Zoé"]) == "Inès, Nathan et 3 autres")
        let group = Conversation.group("g1", members: [.alice, ines, nathan]).group!
        #expect(group.title(ownID: UserSummary.alice.id) == "Inès et Nathan")
        var named = group
        named.name = "Vacances"
        #expect(named.title(ownID: UserSummary.alice.id) == "Vacances")
    }

    @Test("« Vu par » : membres qui ont lu le message, sauf soi ; au-delà de 3, leur nombre")
    func seenBy() {
        var group = Conversation.group("g1", members: [.alice, ines, nathan]).group!
        group.members[0].lastReadMessageID = "m5"
        group.members[1].lastReadMessageID = "m5"
        group.members[2].lastReadMessageID = "m4"
        let m4 = DirectMessage.sample("m4", in: "g1", from: UserSummary.alice.id)
        let m5 = DirectMessage.sample("m5", in: "g1", from: UserSummary.alice.id)
        #expect(GroupRules.seenLabel(group.seenBy(m5, ownID: UserSummary.alice.id)) == "Vu par Inès")
        #expect(GroupRules.seenLabel(group.seenBy(m4, ownID: UserSummary.alice.id)) == "Vu par Inès, Nathan")
        #expect(GroupRules.seenLabel(group.seenBy(.sample("m6", in: "g1"), ownID: UserSummary.alice.id)) == nil)
        // Nathan ajouté après le message : son repère (posé à son entrée) ne vaut pas lecture.
        group.members[2] = GroupMember(user: nathan, joinedAt: m5.createdAt.addingTimeInterval(60), lastReadMessageID: "m5")
        #expect(GroupRules.seenLabel(group.seenBy(m5, ownID: UserSummary.alice.id)) == "Vu par Inès")
        #expect(GroupRules.seenLabel([ines, nathan, lea, .bob]) == "Vu par 4")
    }

    @Test("« en train d'écrire » et nombre d'amis à la création")
    func typingAndCreation() {
        #expect(GroupRules.typingLabel([]) == nil)
        #expect(GroupRules.typingLabel(["Inès"]) == "Inès écrit…")
        #expect(GroupRules.typingLabel(["Inès", "Nathan"]) == "Inès et Nathan écrivent…")
        #expect(GroupRules.typingLabel(["Inès", "Nathan", "Léa"]) == "3 personnes écrivent…")
        #expect(!GroupRules.canCreate(selected: 1))
        #expect(GroupRules.canCreate(selected: 2))
        #expect(GroupRules.canCreate(selected: 31))
        #expect(!GroupRules.canCreate(selected: 32))
        #expect(GroupRules.cleanedName("   ") == nil)
        #expect(GroupRules.cleanedName(" Ciné ") == "Ciné")
    }

    @Test("lignes d'événement, vues par l'auteur, par le membre visé ou par un autre")
    func events() {
        let me = UserSummary.alice.id
        #expect(GroupEvent(kind: .created, user: nil, name: nil).text(actor: ines, ownID: me) == "Inès a créé le groupe")
        #expect(GroupEvent(kind: .created, user: nil, name: nil).text(actor: .alice, ownID: me) == "Tu as créé le groupe")
        #expect(GroupEvent(kind: .added, user: nathan, name: nil).text(actor: ines, ownID: me) == "Inès a ajouté Nathan")
        #expect(GroupEvent(kind: .added, user: .alice, name: nil).text(actor: ines, ownID: me) == "Inès t’a ajouté(e) au groupe")
        #expect(GroupEvent(kind: .removed, user: nathan, name: nil).text(actor: .alice, ownID: me) == "Tu as retiré Nathan")
        #expect(GroupEvent(kind: .removed, user: nil, name: nil).text(actor: ines, ownID: me) == "Inès a retiré un compte supprimé")
        #expect(GroupEvent(kind: .left, user: nil, name: nil).text(actor: nathan, ownID: me) == "Nathan a quitté le groupe")
        #expect(GroupEvent(kind: .renamed, user: nil, name: "Ciné").text(actor: ines, ownID: me) == "Inès a renommé le groupe « Ciné »")
        #expect(GroupEvent(kind: .renamed, user: nil, name: nil).text(actor: nil, ownID: me) == "Un compte supprimé a retiré le nom du groupe")
    }

    @Test("aperçu d'un message de groupe : « Inès : … », « Toi : … »")
    func preview() {
        #expect(groupMessage("m1", from: ines).preview(ownID: UserSummary.alice.id, inGroup: true) == "Inès : Salut")
        #expect(groupMessage("m1", from: .alice).preview(ownID: UserSummary.alice.id, inGroup: true) == "Toi : Salut")
    }
}

@MainActor
@Suite("Chats de groupe : choix d'amis")
struct FriendPickerTests {
    let relationships = FakeRelationshipRepository()
    let search = FakeSearchRepository()
    let repository = FakeMessagingRepository()

    init() {
        relationships.state.withLock {
            $0.follows[.following] = [
                FollowEntry(user: ines, followedAt: .now, viewer: FollowViewer(following: true, followedBy: true)),
                // Suivi sans retour : pas un ami.
                FollowEntry(user: .bob, followedAt: .now, viewer: FollowViewer(following: true, followedBy: false)),
                FollowEntry(user: nathan, followedAt: .now, viewer: FollowViewer(following: true, followedBy: true)),
                FollowEntry(user: lea, followedAt: .now, viewer: FollowViewer(following: true, followedBy: true)),
            ]
        }
        search.state.withLock {
            $0.accounts["na"] = [
                AccountSearchPage(
                    results: [
                        AccountSearchResult(user: nathan, followersCount: 3, viewer: FollowViewer(following: true, followedBy: true)),
                        AccountSearchResult(user: .bob, followersCount: 3, viewer: FollowViewer(following: false, followedBy: true)),
                    ], nextCursor: nil)
            ]
        }
    }

    func makeModel(_ mode: FriendPickerModel.Mode = .create) async -> FriendPickerModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        return FriendPickerModel(
            mode: mode,
            loadFriends: LoadFriendsUseCase(relationships: relationships, search: search),
            createGroup: CreateGroupUseCase(messaging: repository),
            session: session,
            searchDelay: .zero
        )
    }

    @Test("« Suggéré » : seulement les amis ; création possible à partir de 2, dans l'ordre du choix")
    func createGroup() async throws {
        let model = await makeModel()
        await model.loadFirstIfNeeded()
        #expect(model.displayed.map(\.username) == ["ines", "nathan", "lea"])
        model.toggle(nathan)
        #expect(!model.canSubmit)
        #expect(model.hint == "Choisis au moins 2 amis.")
        model.toggle(ines)
        #expect(model.canSubmit)
        #expect(model.submitTitle == "Créer (2)")
        model.toggle(nathan)
        model.toggle(nathan)
        let conversation = try #require(await model.create())
        #expect(repository.calls.last == "createGroup:ines-id,nathan-id")
        #expect(conversation.group?.members.map(\.user.username) == ["alice", "ines-id", "nathan-id"])
    }

    @Test("recherche par nom ou pseudo : amis seulement")
    func searchFriends() async {
        let model = await makeModel()
        model.query = "na"
        #expect(await eventually { model.results != nil })
        #expect(model.displayed.map(\.username) == ["nathan"])
        model.query = ""
        #expect(model.results == nil)
    }

    @Test("ajout de membres : ni les membres actuels, ni plus que les places restantes")
    func addMembers() async {
        let model = await makeModel(.add(conversationID: "g1", members: [ines.id], remaining: 1))
        await model.loadFirstIfNeeded()
        #expect(model.displayed.map(\.username) == ["nathan", "lea"])
        model.toggle(nathan)
        model.toggle(lea)
        #expect(model.selected.map(\.username) == ["nathan"])
        #expect(model.canSubmit)
        #expect(model.submitTitle == "Ajouter (1)")
    }
}

@MainActor
@Suite("Chats de groupe : conversation")
struct GroupConversationTests {
    let repository = FakeMessagingRepository()
    let channel = FakeRealtimeChannel()

    init() {
        let messages = [
            groupMessage("m10", from: ines, content: "", event: GroupEvent(kind: .created, user: nil, name: nil)),
            groupMessage("m11", from: .alice, content: "Salut le groupe"),
        ]
        repository.add(.group("g1", members: [ines, .alice, nathan], lastMessage: messages.last), messages: messages)
    }

    func makeViewModel() async -> (ConversationViewModel, MessagingModel) {
        let (messaging, session) = await makeMessaging(repository, channel: channel)
        let viewModel = ConversationViewModel(
            route: ConversationRoute(id: "g1"),
            loadConversation: LoadConversationUseCase(messaging: repository),
            loadMessages: LoadMessagesUseCase(messaging: repository),
            sendMessage: SendMessageUseCase(messaging: repository),
            markRead: MarkConversationReadUseCase(messaging: repository),
            answerRequest: AnswerMessageRequestUseCase(messaging: repository),
            deleteConversation: DeleteConversationUseCase(messaging: repository),
            deleteMessage: DeleteMessageUseCase(messaging: repository),
            manageGroup: ManageGroupUseCase(messaging: repository),
            messaging: messaging,
            session: session,
            analytics: makeAnalytics()
        )
        return (viewModel, messaging)
    }

    @Test("ouverture par identifiant : titre, administrateur, « Vu par » sous son dernier message")
    func load() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        #expect(repository.calls.first == "conversation:g1")
        #expect(viewModel.title == "Inès et Nathan")
        #expect(!viewModel.isAdmin)
        #expect(viewModel.seen == nil)
        viewModel.read(by: nathan.id, upTo: "m11")
        #expect(viewModel.seen?.messageID == "m11")
        #expect(viewModel.seen?.label == "Vu par Nathan")
        viewModel.read(by: ines.id, upTo: "m11")
        #expect(viewModel.seen?.label == "Vu par Inès, Nathan")
    }

    @Test("« Inès écrit… », effacé par son message")
    func typing() async {
        let (viewModel, messaging) = await makeViewModel()
        await viewModel.load()
        messaging.handle(.typing(conversationID: "g1", userID: ines.id))
        messaging.handle(.typing(conversationID: "g1", userID: nathan.id))
        #expect(viewModel.typingLabel == "Inès et Nathan écrivent…")
        messaging.handle(.messageCreated(groupMessage("m12", from: ines), .zero))
        #expect(viewModel.typingLabel == "Nathan écrit…")
    }

    @Test("ligne d'événement reçue : ni non lue, et le groupe est relu (membres, nom)")
    func eventReloads() async {
        let (viewModel, messaging) = await makeViewModel()
        await messaging.inbox.loadFirst()
        await viewModel.load()
        repository.update("g1") { $0.group?.name = "Ciné" }
        let renamed = groupMessage("m12", from: ines, content: "Ciné", event: GroupEvent(kind: .renamed, user: nil, name: "Ciné"))
        messaging.handle(.messageCreated(renamed, .zero))
        #expect(viewModel.messages.last?.id == "m12")
        #expect(await eventually { viewModel.title == "Ciné" })
        #expect(messaging.inbox.items.first?.unreadCount == 0)
    }

    @Test("renommer, ajouter, sourdine : la ligne de la boîte de réception suit")
    func manage() async {
        let (viewModel, messaging) = await makeViewModel()
        await messaging.inbox.loadFirst()
        await viewModel.load()
        #expect(await viewModel.rename(to: "  Vacances "))
        #expect(repository.calls.contains("rename:Vacances"))
        #expect(viewModel.title == "Vacances")
        #expect(messaging.inbox.items.first?.title(ownID: UserSummary.alice.id) == "Vacances")
        #expect(await viewModel.addMembers([lea]))
        #expect(viewModel.group?.members.count == 4)
        await viewModel.setMuted(true)
        #expect(viewModel.group?.muted == true)
        #expect(repository.calls.last == "mute")
    }

    @Test("sourdine refusée : l'interrupteur revient")
    func muteFails() async {
        let (viewModel, _) = await makeViewModel()
        await viewModel.load()
        repository.fail(with: .rejected("Non"))
        await viewModel.setMuted(true)
        #expect(viewModel.group?.muted == false)
        #expect(viewModel.errorMessage == "Non")
    }

    @Test("l'administrateur retire un membre ; quitter ferme l'écran et retire la ligne")
    func removeAndLeave() async {
        repository.update("g1") { $0.group?.adminID = UserSummary.alice.id }
        let (viewModel, messaging) = await makeViewModel()
        await messaging.inbox.loadFirst()
        await viewModel.load()
        #expect(viewModel.isAdmin)
        await viewModel.removeMember(nathan)
        #expect(repository.calls.last == "remove:nathan-id")
        #expect(viewModel.group?.members.map(\.user.username) == ["ines", "alice"])
        await viewModel.leave()
        #expect(viewModel.isClosed)
        #expect(messaging.inbox.items.isEmpty)
    }

    @Test("modèle partagé : une lecture d'un membre met à jour son repère dans la ligne")
    func readInRow() async {
        let (_, messaging) = await makeViewModel()
        await messaging.inbox.loadFirst()
        messaging.handle(.conversationRead(conversationID: "g1", readerID: ines.id, lastReadMessageID: "m11", .zero))
        #expect(messaging.inbox.items.first?.group?.members.first { $0.user.id == ines.id }?.lastReadMessageID == "m11")
    }

    @Test("partage d'une vidéo : les groupes parmi les conversations récentes, envoi dans le groupe")
    func shareToGroup() async {
        let (messaging, session) = await makeMessaging(repository, channel: channel)
        let interactionRepository = FakeInteractionRepository()
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: interactionRepository),
            setFollow: SetFollowUseCase(interactions: interactionRepository),
            recordShare: ShareVideoUseCase(interactions: interactionRepository),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: makeAnalytics()
        )
        let viewModel = SendVideoViewModel(
            video: .sample("v1"),
            messaging: messaging,
            loadFollows: LoadFollowsUseCase(relationships: FakeRelationshipRepository()),
            share: ShareVideoByMessageUseCase(messaging: repository),
            interactions: interactions,
            session: session
        )
        await viewModel.load()
        #expect(viewModel.recent.map(\.title) == ["Inès et Nathan"])
        #expect(viewModel.recent.first?.avatars.map(\.username) == ["ines", "nathan"])
        await viewModel.send(to: viewModel.recent[0])
        #expect(viewModel.deliveries["g1"] == .sent)
        #expect(repository.sentVideoIDs == ["v1"])
        #expect(!repository.calls.contains { $0.hasPrefix("open:") })
    }
}
