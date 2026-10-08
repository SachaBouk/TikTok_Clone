import Foundation

// Mesure d'audience (ADR-013) : événements envoyés à PostHog. Le catalogue est ici, en un seul endroit ; les noms
// suivent la convention PostHog (anglais, snake_case). Aucune donnée personnelle : identifiants de vidéo, de compte
// auteur et de conversation seulement, jamais de texte saisi (choix du développeur, comme l'identification).
enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

struct AnalyticsEvent: Equatable, Sendable {
    let name: String
    let properties: [String: AnalyticsValue]
}

// Écran où une vidéo est lue.
enum VideoSource: String, Sendable {
    // Feed principal (« Pour toi »).
    case feed
    // Feed des abonnements (ADR-048).
    case following
    // Lecteur vertical ouvert depuis une grille (profil, historique).
    case list
    // Vidéo seule (lien, notification, message).
    case detail
}

// Écran d'où le paywall est ouvert.
enum PaywallSource: String, Hashable, Sendable {
    case profile
    case settings
    // « Recharger » de la feuille de cadeaux (ADR-050).
    case gift
}

// Comment la vidéo a cessé d'être regardée.
enum WatchExit: String, Sendable {
    // Passage à une autre vidéo (moment du swipe).
    case swipe
    // Écran quitté, onglet changé, app en arrière-plan, feed rechargé.
    case leave
}

extension AnalyticsEvent {
    // Durée de visionnage, taux de complétion et moment du swipe (métriques de l'ADR-013).
    static func videoWatched(_ watch: VideoWatch) -> AnalyticsEvent {
        var properties: [String: AnalyticsValue] = [
            "video_id": .string(watch.videoID),
            "author_id": .string(watch.authorID),
            "source": .string(watch.source.rawValue),
            "exit": .string(watch.exit.rawValue),
            "watch_ms": .int(watch.watched.milliseconds),
        ]
        if let duration = watch.duration {
            properties["duration_ms"] = .int(duration.milliseconds)
        }
        if let completion = watch.completion {
            properties["completion"] = .double(completion)
            properties["completed"] = .bool(watch.completed)
            properties["loops"] = .int(watch.loops)
        }
        if let position = watch.exitPosition {
            properties["exit_position_ms"] = .int(position.milliseconds)
        }
        return AnalyticsEvent(name: "video_watched", properties: properties)
    }

    // Like, favori, republication (bouton ou double toucher), et leur retrait.
    static func videoReaction(_ kind: ReactionKind, active: Bool, videoID: String, doubleTap: Bool = false) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "video_reaction",
            properties: [
                "video_id": .string(videoID),
                "kind": .string(kind.analyticsName),
                "active": .bool(active),
                "trigger": .string(doubleTap ? "double_tap" : "button"),
            ])
    }

    static func commentPosted(videoID: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "comment_posted", properties: ["video_id": .string(videoID)])
    }

    // Partage envoyé : feuille système, ou message de l'app.
    static func videoShared(videoID: String, byMessage: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "video_shared",
            properties: [
                "video_id": .string(videoID),
                "method": .string(byMessage ? "message" : "system"),
            ])
    }

    static func followChanged(userID: String, active: Bool) -> AnalyticsEvent {
        AnalyticsEvent(name: "follow_changed", properties: ["user_id": .string(userID), "active": .bool(active)])
    }

    // Signalement envoyé (ADR-038) : type de cible et motif, jamais la précision saisie.
    static func reportSubmitted(target: ReportTarget, reason: ReportReason) -> AnalyticsEvent {
        AnalyticsEvent(name: "report_submitted", properties: ["target_type": .string(target.analyticsName), "reason": .string(reason.rawValue)])
    }

    static func messageSent(conversationID: String, status: ConversationStatus) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "message_sent",
            properties: [
                "conversation_id": .string(conversationID),
                "conversation_status": .string(status.analyticsName),
            ])
    }

    // Parcours d'onboarding : feuille de connexion affichée, inscription commencée puis terminée, connexion.
    static let authSheetShown = AnalyticsEvent(name: "auth_sheet_shown", properties: [:])
    static let signupStarted = AnalyticsEvent(name: "signup_started", properties: [:])
    static let signupCompleted = AnalyticsEvent(name: "signup_completed", properties: [:])
    static let loginCompleted = AnalyticsEvent(name: "login_completed", properties: [:])

    // Expérience « invitation invité » : invitation affichée (variante seulement).
    static let guestPromptShown = AnalyticsEvent(name: "guest_prompt_shown", properties: [:])

    // Paywall (ADR-009) : affiché (depuis le profil ou les paramètres), achat commencé, validé par le store ou annulé.
    // Cadeau envoyé (ADR-050) : code et prix, vidéo et son auteur ; jamais le solde.
    static func giftSent(code: String, amount: Int, videoID: String, authorID: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "gift_sent",
            properties: ["gift_code": .string(code), "amount": .int(amount), "video_id": .string(videoID), "author_id": .string(authorID)])
    }

    static func paywallViewed(source: PaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(name: "paywall_viewed", properties: ["source": .string(source.rawValue)])
    }

    static func tokenPurchaseStarted(productID: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "token_purchase_started", properties: ["product_id": .string(productID)])
    }

    static func tokenPurchaseCompleted(productID: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "token_purchase_completed", properties: ["product_id": .string(productID)])
    }

    static func tokenPurchaseCancelled(productID: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "token_purchase_cancelled", properties: ["product_id": .string(productID)])
    }

    // Publication : envoi commencé, vidéo publiée ou en échec.
    static let uploadStarted = AnalyticsEvent(name: "video_upload_started", properties: [:])
    static func uploadFinished(ready: Bool) -> AnalyticsEvent {
        AnalyticsEvent(name: ready ? "video_published" : "video_processing_failed", properties: [:])
    }

    // Stories (ADR-051) : publication, visionnage (source : rangée, profil, feed), like et réponse par message.
    static func storyUploadStarted(photo: Bool) -> AnalyticsEvent {
        AnalyticsEvent(name: "story_upload_started", properties: ["media_type": .string(photo ? "photo" : "video")])
    }

    static func storyPublished(ready: Bool) -> AnalyticsEvent {
        AnalyticsEvent(name: ready ? "story_published" : "story_processing_failed", properties: [:])
    }

    static func storyViewed(_ story: Story, source: StorySource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "story_viewed",
            properties: [
                "story_id": .string(story.id), "author_id": .string(story.author.id), "media_type": .string(story.mediaType.rawValue),
                "source": .string(source.rawValue),
            ])
    }

    static func storyLiked(_ story: Story) -> AnalyticsEvent {
        AnalyticsEvent(name: "story_liked", properties: ["story_id": .string(story.id), "author_id": .string(story.author.id)])
    }

    static func storyReplySent(_ story: Story) -> AnalyticsEvent {
        AnalyticsEvent(name: "story_reply_sent", properties: ["story_id": .string(story.id), "author_id": .string(story.author.id)])
    }
}

extension ReactionKind {
    var analyticsName: String {
        switch self {
        case .like: "like"
        case .favorite: "favorite"
        case .repost: "repost"
        }
    }
}

extension ConversationStatus {
    var analyticsName: String {
        switch self {
        case .direct: "direct"
        case .requestSent: "request_sent"
        case .requestReceived: "request_received"
        }
    }
}

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
