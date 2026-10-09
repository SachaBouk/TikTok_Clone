// Port de la messagerie directe (module messaging).
protocol MessagingRepository: Sendable {
    // Boîte de réception : conversations acceptées et demandes envoyées, de la plus récemment active à la plus ancienne.
    func conversations(cursor: String?) async throws -> ConversationPage
    // Demandes reçues en attente.
    func requests(cursor: String?) async throws -> ConversationPage
    // La conversation avec ce compte : l'existante, sinon une nouvelle, vide.
    func open(username: String) async throws -> Conversation
    func conversation(id: String) async throws -> Conversation
    func badges() async throws -> MessagingBadges
    // Du plus récent au plus ancien.
    func messages(conversationID: String, cursor: String?) async throws -> MessagePage
    // Texte, vidéo partagée, ou les deux.
    // `clientMessageID` (ADR-044) : renvoyer le même rend le message déjà créé.
    func send(conversationID: String, content: String?, videoID: String?, clientMessageID: String?) async throws -> DirectMessage
    // Réponse à une story de l'autre participant (ADR-051) : texte obligatoire.
    func replyToStory(conversationID: String, storyID: String, content: String, clientMessageID: String) async throws -> DirectMessage
    // Partage d'un live en cours (ADR-053) ; lève AppError.rejected si le live est terminé.
    func shareLive(conversationID: String, liveID: String) async throws -> DirectMessage
    // Lu jusqu'à `upToID` (tout si nil) ; renvoie les badges.
    func markRead(conversationID: String, upToID: String?) async throws -> MessagingBadges
    func accept(conversationID: String) async throws -> Conversation
    func decline(conversationID: String) async throws
    // Pour soi seulement : l'autre garde tout.
    func deleteConversation(id: String) async throws
    // Retrait par l'expéditeur, pour les deux.
    func deleteMessage(id: String) async throws
}
