import Foundation

// Notifications dans l'app (ADR-078) : sans compte Apple Developer, pas de push APNs sur l'iPhone ; un bandeau en haut
// de l'écran annonce, app ouverte, ce que le temps réel apporte (message, activité, live d'un compte suivi, publication
// terminée). Règles pures : contenu, regroupement, silence.

// Sortes de bandeaux, réglables une par une sur l'appareil (Paramètres › Notifications). Les décisions de modération
// n'en ont pas : toujours annoncées.
enum InAppBannerCategory: String, CaseIterable, Identifiable, Sendable {
    case messages, likes, comments, followers, gifts, lives, publications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: "Messages"
        case .likes: "J’aime et republications"
        case .comments: "Commentaires et mentions"
        case .followers: "Nouveaux abonnés"
        case .gifts: "Cadeaux"
        case .lives: "Lives des comptes suivis"
        case .publications: "Mes publications"
        }
    }

    var systemImage: String {
        switch self {
        case .messages: "message"
        case .likes: "heart"
        case .comments: "text.bubble"
        case .followers: "person.badge.plus"
        case .gifts: "gift"
        case .lives: "dot.radiowaves.left.and.right"
        case .publications: "square.and.arrow.up"
        }
    }

    // nil : décision de modération, toujours annoncée.
    static func of(_ kind: ActivityKind) -> InAppBannerCategory? {
        switch kind {
        case .like, .repost, .commentLike: .likes
        case .comment, .commentReply, .mention, .videoMention: .comments
        case .follow: .followers
        case .gift: .gifts
        case .live: .lives
        case .reportResolved, .contentRemoved: nil
        }
    }
}

struct InAppBanner: Identifiable, Equatable, Sendable {
    // Écran ouvert au toucher (AppRouter).
    enum Target: Equatable, Sendable {
        case conversation(Conversation)
        case video(String)
        case profile(username: String)
        case live(String)
        // Centre d'activité (décision de modération).
        case activity
        // Page « Publications » de son profil (envoi en échec).
        case publications
        // Ses stories (story publiée).
        case ownStories
    }

    // Change à chaque nouveau contenu : le bandeau affiché est remplacé (et sa durée repart).
    let id = UUID()
    // Bandeaux de même clé regroupés : conversation, groupe d'activité (même clé que l'API), publication.
    let key: String
    let category: InAppBannerCategory?
    let title: String
    let body: String
    // Photo à gauche (sinon `symbol`), miniature de la vidéo à droite.
    var avatarURL: URL? = nil
    var symbol: String? = nil
    var thumbnailURL: URL? = nil
    let target: Target
    // Activité : le groupe affiché, pour fusionner la notification suivante (« Inès et Nathan ont aimé ta vidéo »).
    var group: ActivityGroup? = nil

    // Conversation du bandeau d'un message (silence quand elle est ouverte).
    var conversationID: String? {
        if case .conversation(let conversation) = target { conversation.id } else { nil }
    }

    // Phrase lue par VoiceOver.
    var spokenText: String { "\(title), \(body)" }
}

// Ce qui est à l'écran au moment où le bandeau arriverait.
struct InAppBannerContext: Equatable, Sendable {
    // Onboarding (ADR-055, ADR-075), création (caméra, éditeur, publication, ADR-062), live regardé ou lancé (ADR-053).
    var isOnboardingShown = false
    var isCreating = false
    var isWatchingLive = false
    // Conversations ouvertes (écran de conversation, même recouvert de ses réglages).
    var openConversationIDs: Set<String> = []
    // Liste des conversations de l'onglet Messages à l'écran : les messages s'y voient déjà.
    var isInboxListShown = false
    // Centre d'activité à l'écran : les notifications s'y voient déjà.
    var isActivityShown = false
}

enum InAppBannerRules {
    // Durée d'affichage d'un bandeau (prolongée tant que le doigt est posé dessus).
    static let displayDuration: Duration = .seconds(4)
    // Bandeaux en attente au plus : au-delà, les plus anciens sont oubliés (ils restent dans l'activité et les messages).
    static let maxQueued = 3
    // Longueur du texte (comme les push de l'API, `PUSH_BODY_MAX_LENGTH`).
    static let maxBodyLength = 140

    // Faut-il afficher ce bandeau ?
    static func shouldShow(_ banner: InAppBanner, context: InAppBannerContext, disabled: Set<InAppBannerCategory>) -> Bool {
        if context.isOnboardingShown || context.isCreating || context.isWatchingLive { return false }
        if let category = banner.category, disabled.contains(category) { return false }
        if let conversationID = banner.conversationID {
            return !context.openConversationIDs.contains(conversationID) && !context.isInboxListShown
        }
        if banner.group != nil, context.isActivityShown { return false }
        return true
    }

    // Activité (`notificationCreated`). `previous` : bandeau de même clé encore affiché ou en attente, regroupé.
    static func activity(_ notification: ActivityNotification, merging previous: InAppBanner? = nil) -> InAppBanner {
        let group = ActivityGroup.merging(notification, into: previous?.group)
        let target: InAppBanner.Target =
            if notification.kind.isModeration {
                .activity
            } else if notification.kind == .live, let liveID = notification.liveID {
                .live(liveID)
            } else if let video = notification.video {
                .video(video.id)
            } else if let actor = notification.actor {
                .profile(username: actor.username)
            } else {
                .activity
            }
        return InAppBanner(
            key: group.key, category: InAppBannerCategory.of(notification.kind), title: group.actorNames,
            body: bounded(group.summary), avatarURL: notification.actor?.avatarURL,
            symbol: notification.kind.isModeration ? "checkmark.shield" : (notification.actor == nil ? "bell" : nil),
            thumbnailURL: notification.video?.thumbnailURL, target: target, group: group)
    }

    // Message reçu (`messageCreated`), dans sa conversation. nil : son propre message (autre appareil), ligne
    // d'événement d'un groupe, groupe en sourdine.
    static func message(_ message: DirectMessage, in conversation: Conversation, ownID: String?) -> InAppBanner? {
        guard message.senderID != ownID, message.event == nil, conversation.group?.muted != true else { return nil }
        let text = message.preview(ownID: ownID, inGroup: conversation.isGroup)
        let sender = conversation.isGroup ? message.sender : conversation.participant
        let body = conversation.status == .requestReceived ? "Demande de message : \(text)" : text
        return InAppBanner(
            key: "conversation:\(conversation.id)", category: .messages, title: conversation.title(ownID: ownID), body: bounded(body),
            avatarURL: sender?.avatarURL ?? conversation.avatars(ownID: ownID).first?.avatarURL, symbol: sender == nil ? "message" : nil,
            thumbnailURL: message.sharedVideo?.thumbnailURL, target: .conversation(conversation))
    }

    // Fin du traitement d'une de ses publications (`videoProcessed`, `storyProcessed`). nil : ni prête ni en échec.
    static func publication(_ video: OwnVideo, isStory: Bool) -> InAppBanner? {
        switch video.status {
        case .ready:
            return InAppBanner(
                key: "publication:\(video.id)", category: .publications, title: isStory ? "Story publiée" : "Vidéo publiée",
                body: isStory ? "Ta story est en ligne pour 24 h." : "Ta vidéo est en ligne.", symbol: "checkmark.circle.fill",
                thumbnailURL: video.thumbnailURL, target: isStory ? .ownStories : .video(video.id))
        case .failed:
            return InAppBanner(
                key: "publication:\(video.id)", category: .publications, title: "Échec de la publication",
                body: isStory ? "Ta story n’a pas pu être traitée." : "Ta vidéo n’a pas pu être traitée. Réessaie avec un autre fichier.",
                symbol: "exclamationmark.triangle.fill", thumbnailURL: video.thumbnailURL, target: .publications)
        case .uploading, .processing:
            return nil
        }
    }

    static func bounded(_ text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        guard single.count > maxBodyLength else { return single }
        return String(single.prefix(maxBodyLength - 1)) + "…"
    }
}

// Sortes de bandeaux coupées sur cet appareil (Paramètres › Notifications).
protocol InAppBannerSettingsStore: Sendable {
    var disabledBannerCategories: Set<InAppBannerCategory> { get }
    func setDisabledBannerCategories(_ categories: Set<InAppBannerCategory>)
}
