import Foundation

// Phrases lues par VoiceOver dans la messagerie, les commentaires, l'activité, les stories et les lives (ADR-076).
// Règles pures, testées sans SwiftUI ; les écrans les posent en libellés, valeurs et annonces.

// Âge d'un contenu, dit en toutes lettres (l'écran affiche « 3 h » ou « 25/09 », mal lus par VoiceOver).
enum SocialAge {
    /// « à l'instant », « il y a 5 minutes », « il y a 3 heures », « hier », « il y a 4 jours », puis « le 25 septembre »
    /// (avec l'année si elle diffère).
    static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "à l’instant" }
        if seconds < 3600 { return "il y a \(SpokenText.count(Int(seconds / 60), "minute", "minutes"))" }
        if seconds < 24 * 3600 { return "il y a \(SpokenText.count(Int(seconds / 3600), "heure", "heures"))" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return "hier" }
        if days < 30 { return "il y a \(SpokenText.count(days, "jour", "jours"))" }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "fr_FR"), calendar: calendar).day().month(.wide)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        style.timeZone = calendar.timeZone
        return "le \(date.formatted(style))"
    }
}

// Messagerie (ADR-076) : bulles, lignes de la boîte de réception, annonces.
enum ConversationSpeech {
    /// Ce que contient un message, sans son expéditeur : réponse à une story, cartes partagées, texte.
    static func content(of message: DirectMessage, isOwn: Bool) -> String {
        var parts: [String?] = []
        if let story = message.story {
            let reply = isOwn ? "En réponse à sa story" : "En réponse à ta story"
            parts.append(story.available ? reply : "\(reply), story expirée")
        }
        if let video = message.sharedVideo {
            if video.available {
                parts.append(video.author.map { "Vidéo partagée de @\($0.username)" } ?? "Vidéo partagée")
                parts.append(video.description)
            } else {
                parts.append("Vidéo indisponible")
            }
        }
        if let live = message.live {
            if live.available {
                parts.append(live.host.map { "Live de @\($0.username), en direct" } ?? "Live en direct")
                parts.append(live.title)
            } else {
                parts.append("Live terminé")
            }
        }
        if let profile = message.profile {
            parts.append(profile.user.map { "Profil partagé : \($0.displayName), @\($0.username)" } ?? "Profil indisponible")
        }
        if let shared = message.collection {
            if let collection = shared.collection {
                parts.append("Collection partagée « \(collection.name) », \(collection.countLabel), de @\(collection.owner.username)")
            } else {
                parts.append("Collection indisponible")
            }
        }
        parts.append(message.content)
        return SpokenText.join(parts)
    }

    /// Nom de l'expéditeur d'un message reçu : dans un groupe, celui du message ; à deux, l'autre participant.
    static func senderName(of message: DirectMessage, participant: UserSummary?, inGroup: Bool) -> String {
        if inGroup { return message.sender?.displayName ?? "Un compte supprimé" }
        return participant?.displayName ?? message.sender?.displayName ?? "Message"
    }

    /// Bulle entière : « Inès : salut, 14:32 », « Toi : à demain, hier, 21:10, vu par Nathan » ; ligne d'événement :
    /// « Inès a créé le groupe, 09:05 ».
    static func label(
        of message: DirectMessage, ownID: String?, participant: UserSummary?, inGroup: Bool, seen: String? = nil, now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if let event = message.event {
            return SpokenText.join([
                event.text(actor: message.sender, ownID: ownID), MessageSpeech.time(message.createdAt, now: now, calendar: calendar),
            ])
        }
        let isOwn = message.senderID == ownID
        let base = MessageSpeech.label(
            sender: senderName(of: message, participant: participant, inGroup: inGroup), isOwn: isOwn, content: content(of: message, isOwn: isOwn),
            sentAt: message.createdAt, now: now, calendar: calendar)
        return SpokenText.join([base, seen.map(lowercasedFirst)])
    }

    /// Message écrit ici, pas encore accepté (ADR-044) : « Toi : salut, envoi en cours » / « Toi : salut, non envoyé ».
    static func outgoingLabel(content: String, state: OutgoingMessage.State) -> String {
        "Toi : \(content), \(state == .sending ? "envoi en cours" : "non envoyé")"
    }

    /// Annonce d'un message arrivé dans la conversation ouverte : « Inès : salut » ; rien pour les siens ni les lignes
    /// d'événement.
    static func arrival(of message: DirectMessage, ownID: String?, participant: UserSummary?, inGroup: Bool) -> String? {
        guard message.senderID != ownID, message.event == nil else { return nil }
        let name = senderName(of: message, participant: participant, inGroup: inGroup)
        return "\(name) : \(content(of: message, isOwn: false))"
    }

    /// « Inès écrit… » (à deux) ; dans un groupe, la phrase de l'écran (« Inès et Nathan écrivent… »).
    static func typing(participant: UserSummary?, groupLabel: String?) -> String {
        groupLabel ?? "\(participant?.displayName ?? "L’autre personne") écrit…"
    }

    /// Ligne de la boîte de réception : « Inès, groupe, Toi : salut, vu, il y a 5 minutes, 2 messages non lus ».
    static func rowLabel(_ conversation: Conversation, ownID: String?, isTyping: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let message = conversation.lastMessage
        var parts: [String?] = [conversation.title(ownID: ownID), conversation.isGroup ? "groupe" : nil]
        if isTyping {
            parts.append("en train d’écrire")
        } else if let message {
            parts.append(message.preview(ownID: ownID, inGroup: conversation.isGroup))
            if !conversation.isGroup, message.senderID == ownID,
                conversation.participantLastReadMessageID.map({ MessageRules.isAtOrBefore(message.id, $0) }) == true
            {
                parts.append("vu")
            } else if !conversation.isGroup, conversation.status == .requestSent {
                parts.append("demande envoyée")
            }
            parts.append(SocialAge.text(message.createdAt, now: now, calendar: calendar))
        }
        if conversation.unreadCount > 0 {
            parts.append(SpokenText.count(conversation.unreadCount, "message non lu", "messages non lus"))
        }
        return SpokenText.join(parts)
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

// Commentaire (ADR-076) : « Nom, Créateur, texte, il y a 2 heures, 12 j'aime, aimé par l'auteur, 3 réponses ».
enum CommentRowSpeech {
    static func label(_ comment: VideoComment, isCreator: Bool, isDisliked: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let who = comment.isReply ? "Réponse de \(comment.author.displayName)" : comment.author.displayName
        if isDisliked { return SpokenText.join([who, "commentaire masqué : tu n’aimes pas ce commentaire"]) }
        return SpokenText.join([
            who,
            isCreator ? "Créateur" : nil,
            comment.content,
            SocialAge.text(comment.createdAt, now: now, calendar: calendar),
            comment.likesCount > 0 ? SpokenText.count(comment.likesCount, "j’aime", "j’aime") : nil,
            comment.viewerLiked == true ? "tu l’aimes" : nil,
            comment.likedByAuthor ? "aimé par l’auteur" : nil,
            !comment.isReply && comment.repliesCount > 0 ? SpokenText.count(comment.repliesCount, "réponse", "réponses") : nil,
        ])
    }

    /// Comptes mentionnés et hashtags du texte, dans l'ordre, sans doublon : actions « Ouvrir @pseudo », « Ouvrir #nom ».
    static func links(in text: String) -> [CommentLink] {
        var links: [(String.Index, CommentLink)] = []
        for occurrence in MentionRules.occurrences(in: text) {
            links.append((occurrence.range.lowerBound, .mention(occurrence.username)))
        }
        for occurrence in HashtagRules.occurrences(in: text) {
            links.append((occurrence.range.lowerBound, .hashtag(occurrence.name)))
        }
        var seen = Set<CommentLink>()
        return links.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
    }

    /// « Commentaire publié » / « Réponse publiée ».
    static func posted(isReply: Bool) -> String {
        isReply ? "Réponse publiée" : "Commentaire publié"
    }
}

enum CommentLink: Hashable, Sendable {
    case mention(String)
    case hashtag(String)

    var actionName: String {
        switch self {
        case .mention(let username): "Ouvrir @\(username)"
        case .hashtag(let name): "Ouvrir #\(name)"
        }
    }
}

// Visionneuse de stories (ADR-076).
enum StoryViewerSpeech {
    /// Libellé du média : « Story de Inès » / « Ta story ».
    static func label(authorName: String, isOwn: Bool) -> String {
        isOwn ? "Ta story" : "Story de \(authorName)"
    }

    /// Valeur : « Story 2 sur 5, photo, il y a 3 heures, en pause ».
    static func value(index: Int, count: Int, mediaType: StoryMediaType, publishedAt: Date, isPaused: Bool, now: Date = .now) -> String {
        SpokenText.join([
            "Story \(SpokenText.ordinal(index, of: max(count, 1)))",
            mediaType == .photo ? "photo" : "vidéo",
            SocialAge.text(publishedAt, now: now),
            isPaused ? "en pause" : nil,
        ])
    }

    /// Annonce à l'arrivée sur une story : « @ines, story 1 sur 3 » / « Ta story, 2 sur 3 ».
    static func arrival(username: String, isOwn: Bool, index: Int, count: Int) -> String {
        let position = SpokenText.ordinal(index, of: max(count, 1))
        return isOwn ? "Ta story, \(position)" : "@\(username), story \(position)"
    }

    /// « 1 vue », « 12 vues ».
    static func viewers(_ count: Int) -> String {
        SpokenText.count(count, "vue", "vues")
    }
}

// Centre d'activité (ADR-076) : « Inès et Nathan ont aimé ta vidéo, il y a 2 heures, non lu ».
enum ActivityRowSpeech {
    static func label(names: String, summary: String, excerpt: String? = nil, createdAt: Date, read: Bool, now: Date = .now) -> String {
        SpokenText.join([
            names.isEmpty ? summary : "\(names) \(summary)",
            excerpt.flatMap { $0.isEmpty ? nil : "« \($0) »" },
            SocialAge.text(createdAt, now: now),
            read ? nil : "non lu",
        ])
    }
}

// Annonces du chat d'un live sans inonder VoiceOver : un message est dit tout de suite si le précédent l'a été il y a
// plus de `interval` ; sinon il attend, et ceux qui attendent sont dits ensemble (les derniers seulement).
struct LiveChatAnnouncer {
    var interval: TimeInterval = 3
    // Messages lus au plus dans une annonce groupée.
    var maxLines = 2
    private(set) var pending: [String] = []
    private var lastAnnouncedAt: Date?

    init(interval: TimeInterval = 3, maxLines: Int = 2) {
        self.interval = interval
        self.maxLines = maxLines
    }

    /// Message reçu : le texte à annoncer tout de suite, ou nil s'il attend (`flush`).
    mutating func receive(_ line: String, at now: Date) -> String? {
        if pending.isEmpty, isDue(at: now) {
            lastAnnouncedAt = now
            return line
        }
        pending.append(line)
        return nil
    }

    /// Délai avant de pouvoir dire les messages en attente ; nil s'il n'y en a pas.
    func delayBeforeFlush(at now: Date) -> TimeInterval? {
        guard !pending.isEmpty else { return nil }
        guard let lastAnnouncedAt else { return 0 }
        return max(0, interval - now.timeIntervalSince(lastAnnouncedAt))
    }

    /// Messages en attente, dits ensemble : « Inès : salut » ou « 5 nouveaux messages. Inès : salut. Nathan : ok ».
    mutating func flush(at now: Date) -> String? {
        guard !pending.isEmpty, isDue(at: now) else { return nil }
        let lines = pending
        pending = []
        lastAnnouncedAt = now
        if lines.count == 1 { return lines[0] }
        let shown = lines.suffix(maxLines).joined(separator: ". ")
        return "\(SpokenText.count(lines.count, "nouveau message", "nouveaux messages")). \(shown)"
    }

    private func isDue(at now: Date) -> Bool {
        guard let lastAnnouncedAt else { return true }
        return now.timeIntervalSince(lastAnnouncedAt) >= interval
    }
}
