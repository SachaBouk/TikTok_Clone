import Foundation
import Synchronization
import Testing

@testable import TikTokClone

final class InMemoryBannerSettings: InAppBannerSettingsStore {
    private let disabled = Mutex(Set<InAppBannerCategory>())

    var disabledBannerCategories: Set<InAppBannerCategory> { disabled.withLock { $0 } }
    func setDisabledBannerCategories(_ categories: Set<InAppBannerCategory>) { disabled.withLock { $0 = categories } }
}

@MainActor
@Suite("Notifications dans l'app")
struct InAppBannerTests {
    let ownID = UserProfile.alice.id
    let settings = InMemoryBannerSettings()

    private func notification(
        _ kind: ActivityKind, id: String = UUID().uuidString, actor: UserSummary? = .bob, video: String? = "v1", comment: String? = nil
    ) -> ActivityNotification {
        ActivityNotification(
            id: id, kind: kind, actor: actor, video: video.map { ActivityNotification.Video(id: $0, thumbnailURL: nil) },
            comment: comment.map { ActivityNotification.Comment(id: "c1", content: $0) }, read: false, createdAt: .now)
    }

    private func conversation(_ id: String = "conv1", status: ConversationStatus = .direct, group: GroupChat? = nil) -> Conversation {
        Conversation(
            id: id, participant: group == nil ? .bob : nil, group: group, status: status, lastMessage: nil, unreadCount: 0,
            participantLastReadMessageID: nil, canSend: true, remainingRequestMessages: nil, blockedByMe: false, createdAt: .now)
    }

    private func message(_ content: String = "salut", in conversation: String = "conv1", from sender: String = UserSummary.bob.id) -> DirectMessage {
        DirectMessage(id: UUID().uuidString, conversationID: conversation, senderID: sender, content: content, sharedVideo: nil, createdAt: .now)
    }

    private func makeModel(_ conversations: [Conversation] = [], context: InAppBannerContext = InAppBannerContext()) -> InAppBannerModel {
        let model = InAppBannerModel(
            settings: settings, ownID: { [ownID] in ownID },
            resolveConversation: { id in conversations.first { $0.id == id } },
            displayDuration: .milliseconds(150), gap: .milliseconds(10))
        model.context = { context }
        return model
    }

    // MARK: - Règles

    @Test("activité : texte de l'activité, vidéo à ouvrir ; abonnement : profil ; live : le live ; modération : l'activité")
    func activityContent() {
        let like = InAppBannerRules.activity(notification(.like))
        #expect(like.title == "Bob")
        #expect(like.body == "a aimé ta vidéo.")
        #expect(like.target == .video("v1"))
        #expect(like.category == .likes)
        #expect(InAppBannerRules.activity(notification(.follow, video: nil)).target == .profile(username: "bob"))
        var live = notification(.live, video: nil)
        live.liveID = "live1"
        #expect(InAppBannerRules.activity(live).target == .live("live1"))
        let moderation = InAppBannerRules.activity(notification(.contentRemoved, actor: nil, video: nil))
        #expect(moderation.target == .activity)
        #expect(moderation.category == nil)
        #expect(InAppBannerRules.activity(notification(.mention, comment: "@alice regarde")).category == .comments)
    }

    @Test("activité regroupée : deux j'aime sur la même vidéo → « Nathan et Bob ont aimé ta vidéo. »")
    func merging() {
        let first = InAppBannerRules.activity(notification(.like))
        let nathan = UserSummary(id: "nathan-id", username: "nathan", displayName: "Nathan", avatarURL: nil)
        let second = InAppBannerRules.activity(notification(.like, actor: nathan), merging: first)
        #expect(second.key == first.key)
        #expect(second.title == "Nathan et Bob")
        #expect(second.body == "ont aimé ta vidéo.")
    }

    @Test("message : nom et texte ; demande reçue ; rien pour le sien, une ligne d'événement ou un groupe en sourdine")
    func messageContent() throws {
        let banner = try #require(InAppBannerRules.message(message(), in: conversation(), ownID: ownID))
        #expect(banner.title == "Bob")
        #expect(banner.body == "salut")
        #expect(banner.conversationID == "conv1")
        let request = try #require(InAppBannerRules.message(message(), in: conversation(status: .requestReceived), ownID: ownID))
        #expect(request.body == "Demande de message : salut")
        #expect(InAppBannerRules.message(message(from: ownID), in: conversation(), ownID: ownID) == nil)
        var event = message()
        event.event = GroupEvent(kind: .renamed, user: nil, name: "Les potes")
        #expect(InAppBannerRules.message(event, in: conversation(), ownID: ownID) == nil)
        let muted = GroupChat(name: "Les potes", adminID: ownID, muted: true, members: [])
        #expect(InAppBannerRules.message(message(), in: conversation(group: muted), ownID: ownID) == nil)
        #expect(InAppBannerRules.bounded(String(repeating: "a", count: 300)).count == InAppBannerRules.maxBodyLength)
    }

    @Test("publication : prête → la vidéo ; en échec → « Publications » ; story → ses stories")
    func publicationContent() {
        let ready = OwnVideo(id: "v9", description: nil, status: .ready, thumbnailURL: nil, createdAt: .now)
        #expect(InAppBannerRules.publication(ready, isStory: false)?.target == .video("v9"))
        #expect(InAppBannerRules.publication(ready, isStory: true)?.target == .ownStories)
        let failed = OwnVideo(id: "v9", description: nil, status: .failed, thumbnailURL: nil, createdAt: .now)
        #expect(InAppBannerRules.publication(failed, isStory: false)?.target == .publications)
        let processing = OwnVideo(id: "v9", description: nil, status: .processing, thumbnailURL: nil, createdAt: .now)
        #expect(InAppBannerRules.publication(processing, isStory: false) == nil)
    }

    @Test("silence : onboarding, création, live, conversation ouverte, liste des messages, activité affichée, sorte coupée")
    func silence() throws {
        let like = InAppBannerRules.activity(notification(.like))
        let chat = try #require(InAppBannerRules.message(message(), in: conversation(), ownID: ownID))
        #expect(InAppBannerRules.shouldShow(like, context: InAppBannerContext(), disabled: []))
        #expect(!InAppBannerRules.shouldShow(like, context: InAppBannerContext(isOnboardingShown: true), disabled: []))
        #expect(!InAppBannerRules.shouldShow(like, context: InAppBannerContext(isCreating: true), disabled: []))
        #expect(!InAppBannerRules.shouldShow(like, context: InAppBannerContext(isWatchingLive: true), disabled: []))
        #expect(!InAppBannerRules.shouldShow(like, context: InAppBannerContext(isActivityShown: true), disabled: []))
        #expect(InAppBannerRules.shouldShow(like, context: InAppBannerContext(isInboxListShown: true), disabled: []))
        #expect(!InAppBannerRules.shouldShow(like, context: InAppBannerContext(), disabled: [.likes]))
        #expect(!InAppBannerRules.shouldShow(chat, context: InAppBannerContext(openConversationIDs: ["conv1"]), disabled: []))
        #expect(InAppBannerRules.shouldShow(chat, context: InAppBannerContext(openConversationIDs: ["autre"]), disabled: []))
        #expect(!InAppBannerRules.shouldShow(chat, context: InAppBannerContext(isInboxListShown: true), disabled: []))
        #expect(InAppBannerRules.shouldShow(chat, context: InAppBannerContext(isActivityShown: true), disabled: []))
        // Modération : jamais coupée par les réglages.
        let moderation = InAppBannerRules.activity(notification(.reportResolved, actor: nil, video: nil))
        #expect(InAppBannerRules.shouldShow(moderation, context: InAppBannerContext(), disabled: Set(InAppBannerCategory.allCases)))
    }

    // MARK: - Modèle

    @Test("temps réel : notification et message deviennent des bandeaux, un à la fois, puis le suivant")
    func queue() async {
        let model = makeModel([conversation()])
        var shown: [String] = []
        model.onShow = { shown.append($0.title) }
        model.handle(.notificationCreated(notification(.follow, video: nil), unreadCount: 1))
        model.handle(.messageCreated(message(), .zero))
        #expect(model.current?.body == "a commencé à te suivre.")
        #expect(await eventually { model.queuedCount == 1 })
        #expect(await eventually { model.current?.conversationID == "conv1" })
        #expect(await eventually { model.current == nil })
        #expect(shown == ["Bob", "Bob"])
    }

    @Test("même clé : le bandeau affiché est remplacé, pas empilé ; au plus 3 en attente")
    func sameKeyAndLimit() {
        let model = makeModel()
        model.handle(.notificationCreated(notification(.like), unreadCount: 1))
        let nathan = UserSummary(id: "nathan-id", username: "nathan", displayName: "Nathan", avatarURL: nil)
        model.handle(.notificationCreated(notification(.like, actor: nathan), unreadCount: 2))
        #expect(model.current?.title == "Nathan et Bob")
        #expect(model.queuedCount == 0)
        for index in 0..<5 { model.handle(.notificationCreated(notification(.comment, comment: "n°\(index)"), unreadCount: 3)) }
        #expect(model.queuedCount == InAppBannerRules.maxQueued)
    }

    @Test("son propre message, publication en traitement, sorte coupée : rien")
    func ignored() async {
        let model = makeModel([conversation()])
        model.handle(.messageCreated(message(from: ownID), .zero))
        model.handle(.videoProcessed(OwnVideo(id: "v", description: nil, status: .processing, thumbnailURL: nil, createdAt: .now)))
        model.setEnabled(false, for: .likes)
        #expect(settings.disabledBannerCategories == [.likes])
        #expect(!model.isEnabled(.likes))
        model.handle(.notificationCreated(notification(.like), unreadCount: 1))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.current == nil)
        model.setEnabled(true, for: .likes)
        #expect(settings.disabledBannerCategories.isEmpty)
    }

    @Test("doigt posé : le bandeau reste ; toucher : son écran, fermé ; déconnexion : tout oublié")
    func gestures() async {
        let model = makeModel()
        model.handle(.notificationCreated(notification(.like), unreadCount: 1))
        model.setHeld(true)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.current != nil)
        #expect(model.open() == .video("v1"))
        #expect(model.current == nil)
        model.handle(.notificationCreated(notification(.repost), unreadCount: 2))
        model.reset()
        #expect(model.current == nil)
    }

    @Test("routeur : la vidéo, le profil, ou l'onglet Messages avec la conversation (écrans par-dessus fermés)")
    func routing() {
        let router = AppRouter()
        let chat = conversation()
        router.open(.video("v1"), me: nil)
        #expect(router.presentedVideo?.id == "v1")
        router.open(.conversation(chat), me: nil)
        #expect(router.presentedVideo == nil)
        #expect(router.tabRequest?.page == .conversation(chat))
        #expect(router.tabRequest?.afterDismissal == true)
        router.open(.profile(username: "bob"), me: nil)
        #expect(router.presentedProfile?.username == "bob")
        router.open(.ownStories, me: .alice)
        #expect(router.presentedStories?.authors == [.alice])
    }
}
