import Foundation
import Testing

@testable import TikTokClone

@Suite("Messagerie : règles")
struct MessagingRulesTests {
    let me = UserProfile.alice.id

    @Test("« Vu » sous son dernier message, s'il est lu par l'autre")
    func seen() {
        let messages: [DirectMessage] = [.sample("m10", from: me), .sample("m11"), .sample("m12", from: me)]
        #expect(MessageRules.seenMessageID(in: messages, ownID: me, participantLastRead: "m12") == "m12")
        #expect(MessageRules.seenMessageID(in: messages, ownID: me, participantLastRead: "m11") == nil)
        #expect(MessageRules.seenMessageID(in: messages, ownID: me, participantLastRead: nil) == nil)
        #expect(MessageRules.seenMessageID(in: [.sample("m11")], ownID: me, participantLastRead: "m11") == nil)
    }

    @Test("horodatage avant le premier message et après une heure sans message")
    func timestamps() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let messages: [DirectMessage] = [
            .sample("m10", at: start),
            .sample("m11", at: start.addingTimeInterval(600)),
            .sample("m12", at: start.addingTimeInterval(600 + 3600)),
        ]
        #expect(MessageRules.timestampedIDs(in: messages) == ["m10", "m12"])
    }

    @Test("texte nettoyé, 1 000 caractères au plus")
    func text() {
        #expect(MessageRules.cleaned("  Salut \n") == "Salut")
        #expect(MessageRules.cleaned(" \n ") == nil)
        #expect(MessageRules.isValid(String(repeating: "a", count: 1000)))
        #expect(!MessageRules.isValid(String(repeating: "a", count: 1001)))
    }

    @Test("demande envoyée : une place de moins à chaque message, plus d'envoi à zéro ; répondre à une demande l'accepte")
    func afterSending() {
        let request = Conversation.sample("c1", status: .requestSent, remaining: 2)
        let once = request.afterSending(.sample("m10", from: me))
        #expect(once.remainingRequestMessages == 1)
        #expect(once.canSend)
        let twice = once.afterSending(.sample("m11", from: me))
        #expect(twice.remainingRequestMessages == 0)
        #expect(!twice.canSend)
        #expect(twice.composerNotice?.contains("Demande envoyée") == true)

        let received = Conversation.sample("c2", status: .requestReceived, unreadCount: 2)
        let answered = received.afterSending(.sample("m12", from: me))
        #expect(answered.status == .direct)
        #expect(answered.unreadCount == 0)
    }

    @Test("« en train d'écrire » et avertissements selon le statut")
    func notices() {
        #expect(Conversation.sample("c1").allowsTyping)
        #expect(!Conversation.sample("c1", status: .requestSent, remaining: 3).allowsTyping)
        #expect(!Conversation.sample("c1", canSend: false).allowsTyping)
        #expect(Conversation.sample("c1", canSend: false, blockedByMe: true).composerNotice?.hasPrefix("Tu as bloqué @bob") == true)
        #expect(Conversation.sample("c1", canSend: false).composerNotice == "Tu ne peux pas écrire à ce compte.")
        #expect(Conversation.sample("c1", status: .requestSent, remaining: 1).composerNotice?.contains("encore 1 message ") == true)
        #expect(Conversation.sample("c1").composerNotice == nil)
    }

    @Test("envoi : texte nettoyé, vide ou trop long refusé sans appel ; partage d'une vidéo par pseudo")
    func sendUseCases() async throws {
        let repository = FakeMessagingRepository()
        repository.add(.sample("c1"))
        let send = SendMessageUseCase(messaging: repository)
        _ = try await send(conversationID: "c1", text: "  Salut  ")
        await #expect(throws: AppError.self) { try await send(conversationID: "c1", text: "   ") }
        await #expect(throws: AppError.self) { try await send(conversationID: "c1", text: String(repeating: "a", count: 1001)) }
        #expect(repository.sentContents == ["Salut"])

        let message = try await ShareVideoByMessageUseCase(messaging: repository)(videoID: "v1", to: "carla")
        #expect(message.sharedVideo?.id == "v1")
        #expect(repository.calls.contains("open:carla"))
        #expect(repository.sentContents.last == .some(nil))
    }
}

@Suite("Feuille « Envoyer à » : règles")
struct ShareRecipientRulesTests {
    @Test("section : lettre sans accent ni casse, « # » pour le reste")
    func section() {
        #expect(ShareRecipientRules.section(for: "Éloïse") == "E")
        #expect(ShareRecipientRules.section(for: "zoé") == "Z")
        #expect(ShareRecipientRules.section(for: "42club") == "#")
        #expect(ShareRecipientRules.section(for: "😎 Max") == "#")
        #expect(ShareRecipientRules.section(for: "") == "#")
    }

    @Test("recherche : nom ou pseudo, « @ » ignoré, sans casse ni accents")
    func matches() {
        #expect(ShareRecipientRules.matches("ines", title: "Inès Moreau", username: "ines.m"))
        #expect(ShareRecipientRules.matches("@INES.", title: "Inès", username: "ines.m"))
        #expect(!ShareRecipientRules.matches("bob", title: "Inès", username: "ines"))
        #expect(ShareRecipientRules.matches("calamar", title: "le jeu du calamar", username: nil))
    }

    @Test("ordre alphabétique : sans accents, les noms sans lettre en dernier")
    func order() {
        let names = ["zoé", "42club", "Éloïse", "adri", "Baetsuji", "baberekn"]
        #expect(names.sorted(by: ShareRecipientRules.precedes) == ["adri", "baberekn", "Baetsuji", "Éloïse", "zoé", "42club"])
    }
}
