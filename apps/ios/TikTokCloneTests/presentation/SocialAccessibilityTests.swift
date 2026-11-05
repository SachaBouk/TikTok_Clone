import Foundation
import Testing

@testable import TikTokClone

// VoiceOver dans la messagerie, les commentaires, l'activité, les stories et les lives (ADR-076).

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

@Suite("VoiceOver : phrases de la messagerie, des commentaires, de l'activité, des stories et des lives (ADR-076)")
struct SocialSpeechTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("âge dit en toutes lettres")
    func age() {
        #expect(SocialAge.text(now.addingTimeInterval(-20), now: now, calendar: paris) == "à l’instant")
        #expect(SocialAge.text(now.addingTimeInterval(-60), now: now, calendar: paris) == "il y a 1 minute")
        #expect(SocialAge.text(now.addingTimeInterval(-5 * 60), now: now, calendar: paris) == "il y a 5 minutes")
        #expect(SocialAge.text(now.addingTimeInterval(-3 * 3600), now: now, calendar: paris) == "il y a 3 heures")
        #expect(SocialAge.text(now.addingTimeInterval(-30 * 3600), now: now, calendar: paris) == "hier")
        #expect(SocialAge.text(now.addingTimeInterval(-4 * 86400), now: now, calendar: paris) == "il y a 4 jours")
        let old = SocialAge.text(now.addingTimeInterval(-60 * 86400), now: now, calendar: paris)
        #expect(old.hasPrefix("le "))
    }

    @Test("bulle : qui, quoi, quand, cartes partagées et « vu »")
    func bubble() {
        let message = DirectMessage.sample("m1", content: "Salut", at: now.addingTimeInterval(-60))
        let label = ConversationSpeech.label(of: message, ownID: UserSummary.alice.id, participant: .bob, inGroup: false, now: now, calendar: paris)
        #expect(label.hasPrefix("Bob : Salut, "))

        let own = DirectMessage.sample("m2", from: UserSummary.alice.id, content: "À demain", at: now.addingTimeInterval(-60))
        let seen = ConversationSpeech.label(
            of: own, ownID: UserSummary.alice.id, participant: .bob, inGroup: false, seen: "Vu", now: now, calendar: paris)
        #expect(seen.hasPrefix("Toi : À demain, "))
        #expect(seen.hasSuffix(", vu"))

        let video = DirectMessage.sample("m3", content: "", sharedVideoID: "v1")
        #expect(ConversationSpeech.content(of: video, isOwn: false) == "Vidéo partagée de @bob")

        var gone = DirectMessage.sample("m4", content: "regarde")
        gone.live = SharedLive(id: "l1", available: false, title: nil, host: .bob)
        #expect(ConversationSpeech.content(of: gone, isOwn: false) == "Live terminé, regarde")

        var profile = DirectMessage.sample("m5", content: "")
        profile.profile = SharedProfile(id: "p1", user: .bob)
        #expect(ConversationSpeech.content(of: profile, isOwn: false) == "Profil partagé : Bob, @bob")
    }

    @Test("groupe : le nom de l'expéditeur à chaque message ; lignes d'événement avec l'heure")
    func groupBubble() {
        var message = DirectMessage.sample("m1", content: "Coucou")
        message.sender = .bob
        #expect(ConversationSpeech.senderName(of: message, participant: nil, inGroup: true) == "Bob")
        message.sender = nil
        #expect(ConversationSpeech.senderName(of: message, participant: nil, inGroup: true) == "Un compte supprimé")

        var event = DirectMessage.sample("m2", content: "")
        event.sender = .bob
        event.event = GroupEvent(kind: .created, user: nil, name: nil)
        let label = ConversationSpeech.label(of: event, ownID: UserSummary.alice.id, participant: nil, inGroup: true, now: now, calendar: paris)
        #expect(label.hasPrefix("Bob a créé le groupe, "))
        #expect(ConversationSpeech.arrival(of: event, ownID: UserSummary.alice.id, participant: nil, inGroup: true) == nil)
    }

    @Test("annonces : message reçu (pas les siens), « en train d'écrire », envoi")
    func announcements() {
        let message = DirectMessage.sample("m1", content: "Salut")
        #expect(ConversationSpeech.arrival(of: message, ownID: UserSummary.alice.id, participant: .bob, inGroup: false) == "Bob : Salut")
        let own = DirectMessage.sample("m2", from: UserSummary.alice.id)
        #expect(ConversationSpeech.arrival(of: own, ownID: UserSummary.alice.id, participant: .bob, inGroup: false) == nil)
        #expect(ConversationSpeech.typing(participant: .bob, groupLabel: nil) == "Bob écrit…")
        #expect(ConversationSpeech.typing(participant: nil, groupLabel: "Inès et Nathan écrivent…") == "Inès et Nathan écrivent…")
        #expect(ConversationSpeech.outgoingLabel(content: "Salut", state: .sending) == "Toi : Salut, envoi en cours")
        #expect(ConversationSpeech.outgoingLabel(content: "Salut", state: .failed) == "Toi : Salut, non envoyé")
    }

    @Test("ligne de la boîte de réception : nom, aperçu, date dite, non lus ; sans « · »")
    func inboxRow() {
        let last = DirectMessage.sample("m1", content: "Salut", at: now.addingTimeInterval(-300))
        let conversation = Conversation.sample("c1", lastMessage: last, unreadCount: 2)
        let label = ConversationSpeech.rowLabel(conversation, ownID: UserSummary.alice.id, isTyping: false, now: now, calendar: paris)
        #expect(label == "Bob, Salut, il y a 5 minutes, 2 messages non lus")
        #expect(!label.contains("·"))
        #expect(
            ConversationSpeech.rowLabel(conversation, ownID: UserSummary.alice.id, isTyping: true, now: now, calendar: paris)
                == "Bob, en train d’écrire, 2 messages non lus")
        let request = Conversation.sample(
            "c2", status: .requestSent, lastMessage: .sample("m2", from: UserSummary.alice.id, at: now.addingTimeInterval(-60)))
        #expect(
            ConversationSpeech.rowLabel(request, ownID: UserSummary.alice.id, isTyping: false, now: now, calendar: paris)
                == "Bob, Toi : Salut, demande envoyée, il y a 1 minute")
    }

    @Test("commentaire : une phrase, nombres en entier, liens en actions")
    func comment() {
        var comment = VideoComment.sample("c1", content: "Trop bien @carla #plage")
        comment.likesCount = 1200
        comment.likedByAuthor = true
        comment.repliesCount = 3
        let label = CommentRowSpeech.label(comment, isCreator: false, isDisliked: false, now: comment.createdAt.addingTimeInterval(7200))
        #expect(label == "Bob, Trop bien @carla #plage, il y a 2 heures, \(SpokenText.number(1200)) j’aime, aimé par l’auteur, 3 réponses")
        #expect(CommentRowSpeech.label(comment, isCreator: true, isDisliked: true).hasPrefix("Bob, commentaire masqué"))
        #expect(CommentRowSpeech.links(in: comment.content) == [.mention("carla"), .hashtag("plage")])
        #expect(CommentLink.mention("carla").actionName == "Ouvrir @carla")

        var reply = VideoComment.sample("r1", content: "Merci", author: .alice)
        reply.parentID = "c1"
        reply.viewerLiked = true
        let replyLabel = CommentRowSpeech.label(reply, isCreator: true, isDisliked: false, now: reply.createdAt)
        #expect(replyLabel == "Réponse de Alice, Créateur, Merci, à l’instant, tu l’aimes")
        #expect(CommentRowSpeech.posted(isReply: true) == "Réponse publiée")
    }

    @Test("story : libellé, valeur et annonce")
    func story() {
        #expect(StoryViewerSpeech.label(authorName: "Bob", isOwn: false) == "Story de Bob")
        #expect(StoryViewerSpeech.label(authorName: "Bob", isOwn: true) == "Ta story")
        #expect(
            StoryViewerSpeech.value(index: 1, count: 5, mediaType: .photo, publishedAt: now.addingTimeInterval(-3 * 3600), isPaused: true, now: now)
                == "Story 2 sur 5, photo, il y a 3 heures, en pause")
        #expect(StoryViewerSpeech.arrival(username: "bob", isOwn: false, index: 0, count: 3) == "@bob, story 1 sur 3")
        #expect(StoryViewerSpeech.arrival(username: "alice", isOwn: true, index: 1, count: 3) == "Ta story, 2 sur 3")
        #expect(StoryViewerSpeech.viewers(1) == "1 vue")
        #expect(StoryViewerSpeech.viewers(1200) == "\(SpokenText.number(1200)) vues")
    }

    @Test("activité : « non lu » dit, extrait cité")
    func activity() {
        #expect(
            ActivityRowSpeech.label(
                names: "Inès et Nathan", summary: "ont aimé ta vidéo.", createdAt: now.addingTimeInterval(-7200), read: false, now: now)
                == "Inès et Nathan ont aimé ta vidéo., il y a 2 heures, non lu")
        #expect(
            ActivityRowSpeech.label(
                names: "Contenu retiré", summary: "Ton commentaire a été retiré.", excerpt: "spam", createdAt: now, read: true, now: now)
                == "Contenu retiré Ton commentaire a été retiré., « spam », à l’instant")
    }

    @Test("live : lignes du chat et cadeaux")
    func liveLines() {
        #expect(LiveChatSpeech.message(.sample("m1", by: .bob, content: "Coucou"), isHost: false) == "Bob : Coucou")
        #expect(LiveChatSpeech.message(.sample("m1", by: .bob, content: "Coucou"), isHost: true) == "Bob, créateur : Coucou")
        #expect(LiveChatSpeech.event(LiveChatEvent(kind: .joined, user: .alice)) == "Alice a rejoint")
        #expect(LiveChatSpeech.gift(sender: .alice, gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹")) == "Alice a envoyé Rose")
    }

    @Test("chat d'un live : au plus une annonce toutes les 3 s, les suivantes regroupées")
    func chatAnnouncer() {
        var announcer = LiveChatAnnouncer()
        #expect(announcer.receive("Bob : 1", at: now) == "Bob : 1")
        #expect(announcer.receive("Bob : 2", at: now.addingTimeInterval(1)) == nil)
        #expect(announcer.receive("Inès : 3", at: now.addingTimeInterval(1.5)) == nil)
        #expect(announcer.receive("Nathan : 4", at: now.addingTimeInterval(2)) == nil)
        #expect(announcer.delayBeforeFlush(at: now.addingTimeInterval(2)) == 1)
        #expect(announcer.flush(at: now.addingTimeInterval(2.5)) == nil)
        #expect(announcer.flush(at: now.addingTimeInterval(3)) == "3 nouveaux messages. Inès : 3. Nathan : 4")
        #expect(announcer.delayBeforeFlush(at: now.addingTimeInterval(3)) == nil)
        // Un message seul après la pause : dit tel quel.
        #expect(announcer.receive("Bob : 5", at: now.addingTimeInterval(4)) == nil)
        #expect(announcer.flush(at: now.addingTimeInterval(6)) == "Bob : 5")
        #expect(announcer.receive("Bob : 6", at: now.addingTimeInterval(10)) == "Bob : 6")
    }
}

// Modèles : règles de VoiceOver posées dans les modèles, pas dans les vues.

extension StoryTests {
    @Test("VoiceOver : une photo n'avance pas seule ; pause, comptes suivant et précédent ; phrases (ADR-076)")
    func voiceOverPlayback() async {
        repository.state.withLock {
            $0.stories["bob"] = [.sample("b1"), .sample("b2")]
            $0.stories["carol"] = [.sample("c1", by: Self.carol)]
        }
        let (viewer, _) = makeViewer([.bob, Self.carol], session: await makeSession())
        await viewer.start()
        viewer.holdsPhotos = true
        viewer.tick(.seconds(10))
        #expect(viewer.current?.id == "b1")
        #expect(viewer.progress == 0)
        #expect(viewer.arrivalSpeech == "@bob, story 1 sur 2")
        #expect(viewer.spokenValue.hasPrefix("Story 1 sur 2, photo, "))

        viewer.togglePause()
        #expect(viewer.isPausedByUser)
        #expect(viewer.spokenValue.hasSuffix("en pause"))
        viewer.togglePause()
        #expect(!viewer.isPaused)

        #expect(!viewer.hasPreviousAuthor)
        viewer.nextAuthor()
        #expect(await eventually { viewer.current?.id == "c1" })
        #expect(viewer.hasPreviousAuthor)
        viewer.previousAuthor()
        #expect(await eventually { viewer.current?.author.id == UserSummary.bob.id })
        viewer.nextAuthor()
        #expect(await eventually { viewer.current?.id == "c1" })
        viewer.nextAuthor()
        #expect(viewer.state == .finished)
    }
}

extension ConversationViewModelTests {
    @Test("VoiceOver : un message reçu est annoncé une fois, pas les siens ; envoi annoncé (ADR-076)")
    func voiceOverAnnouncements() async {
        let (viewModel, messaging) = await makeViewModel()
        var announced: [String] = []
        viewModel.announce = { announced.append($0) }
        await viewModel.load()
        messaging.handle(.messageCreated(.sample("m14", content: "Coucou"), .zero))
        messaging.handle(.messageCreated(.sample("m14", content: "Coucou"), .zero))
        messaging.handle(.messageCreated(.sample("m15", from: UserProfile.alice.id), .zero))
        #expect(announced == ["Bob : Coucou"])
        viewModel.draft = "Salut"
        await viewModel.send()
        #expect(announced.last == "Message envoyé")
        #expect(viewModel.typingSpeech == "Bob écrit…")
    }
}

extension LiveRoomTests {
    @Test("VoiceOver : messages des autres et cadeaux annoncés, sans les siens ni les comptes masqués ; fin annoncée (ADR-076)")
    func voiceOverAnnouncements() async {
        repository.state.withLock { $0.connection = .sample() }
        let model = makeModel(.viewer(liveID: "live-1", source: .link), session: await makeSession(), room: FakeLiveRoom(), hidden: ["carol-id"])
        var announced: [String] = []
        model.announce = { announced.append($0) }
        await model.start()
        model.apply(.event(.chatMessage(.sample("m1", by: .bob, content: "Coucou"))))
        model.apply(.event(.chatMessage(.sample("m2", by: .alice, content: "Moi"))))
        model.apply(.event(.chatMessage(.sample("m3", by: UserSummary(id: "carol-id", username: "carol", displayName: "Carol", avatarURL: nil)))))
        model.apply(.event(.gift(sender: .bob, gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, giftsCount: 1, giftsAmount: 1)))
        #expect(announced.first?.hasSuffix("Coucou") == true)
        #expect(!announced.contains { $0.contains("Moi") || $0.contains("Carol") })
        #expect(announced.contains("Bob a envoyé Rose"))
        model.apply(.event(.ended(.moderation)))
        #expect(await eventually { announced.contains(LiveEndReason.moderation.message) })
    }
}

extension LiveTikTokTests {
    @Test("VoiceOver : live suivant et précédent (ADR-076)")
    func voiceOverMove() async {
        repository.state.withLock { $0.discover = [.sample("l1"), .sample("l2", host: .alice)] }
        let model = LiveFeedModel(load: LoadDiscoverLivesUseCase(lives: repository))
        await model.start()
        #expect(!model.hasPrevious(before: "l1"))
        #expect(!model.move(by: -1))
        #expect(model.move(by: 1))
        #expect(model.currentID == "l2")
        #expect(model.hasPrevious(before: "l2"))
        #expect(!model.move(by: 1))
        #expect(model.move(by: -1))
        #expect(model.currentID == "l1")
    }
}
