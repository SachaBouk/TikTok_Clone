import Foundation

// Stories (ADR-051) : vidéo (60 s au plus) ou photo, visibles 24 h après leur publication, puis supprimées. Publiques ;
// la rangée de la boîte de réception montre sa story et celles de ses abonnements.

enum StoryMediaType: String, Equatable, Sendable {
    case video
    case photo
}

// Chiffres d'une story, pour son auteur seulement.
struct StoryStats: Equatable, Sendable {
    var viewers: Int
    var likes: Int
}

// Une story active, telle que la visionneuse l'affiche.
struct Story: Identifiable, Equatable, Sendable {
    let id: String
    let author: UserSummary
    let mediaType: StoryMediaType
    // Manifeste HLS (vidéo) ou photo.
    let mediaURL: URL
    let thumbnailURL: URL
    let publishedAt: Date
    let expiresAt: Date
    // État du compte connecté (faux en invité et pour ses propres stories).
    var viewed: Bool
    var liked: Bool
    // Ses propres stories seulement.
    var stats: StoryStats?
}

// Un compte de la rangée de stories.
struct StoryTrayEntry: Identifiable, Equatable, Sendable {
    var id: String { user.id }
    let user: UserSummary
    let storiesCount: Int
    let latestAt: Date
    // Au moins une story pas encore vue (toujours faux pour soi).
    var hasUnseen: Bool
}

// Anneau autour d'un avatar : story à voir (coloré) ou déjà vue (gris).
enum StoryRing: Equatable, Sendable {
    case unseen
    case seen

    init(hasUnseen: Bool) {
        self = hasUnseen ? .unseen : .seen
    }
}

// Une personne qui a vu sa story.
struct StoryViewer: Identifiable, Equatable, Sendable {
    var id: String { user.id }
    let user: UserSummary
    let viewedAt: Date
    let liked: Bool
}

struct StoryViewersPage: Equatable, Sendable {
    let viewers: [StoryViewer]
    let nextCursor: String?
    let stats: StoryStats
}

// Story à laquelle répond un message ; indisponible une fois expirée ou supprimée.
struct RepliedStory: Equatable, Sendable {
    let id: String
    let available: Bool
    let mediaType: StoryMediaType?
    let thumbnailURL: URL?
}

// D'où la visionneuse a été ouverte (mesure d'audience, ADR-013).
enum StorySource: String, Equatable, Sendable {
    case tray
    case profile
    case feed
}

// Règles des stories, alignées sur celles de l'API (`stories/domain/story.ts`) et du worker (`media/rules.ts`).
enum StoryRules {
    // Vidéo : 60 secondes au plus, à une seconde près (arrondis du conteneur).
    static let maxVideoDuration: Duration = .seconds(60)
    // Photo : JPEG 9:16 de 1080×1920 px, 5 Mio au plus ; affichée 5 secondes.
    static let photoSize = CGSize(width: 1080, height: 1920)
    static let maxPhotoFileSize = 5 * 1024 * 1024
    static let photoDuration: Duration = .seconds(5)

    static func isTooLong(_ duration: Duration) -> Bool {
        duration > maxVideoDuration + UploadRules.durationTolerance
    }

    // Première story à montrer : la première pas encore vue, sinon la première.
    static func startIndex(of stories: [Story]) -> Int {
        stories.firstIndex { !$0.viewed } ?? 0
    }

    // Recadrage au centre au format 9:16 d'une image de taille `size` (en pixels).
    static func cropRect(for size: CGSize) -> CGRect {
        let target = photoSize.width / photoSize.height
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width / size.height > target {
            let width = (size.height * target).rounded(.down)
            return CGRect(x: ((size.width - width) / 2).rounded(.down), y: 0, width: width, height: size.height)
        }
        let height = (size.width / target).rounded(.down)
        return CGRect(x: 0, y: ((size.height - height) / 2).rounded(.down), width: size.width, height: height)
    }
}

// Position dans la visionneuse : compte de la rangée, puis story de ce compte.
struct StoryPosition: Equatable, Sendable {
    var author: Int
    var story: Int
}

// Navigation de la visionneuse, sans état : où aller après un toucher ou la fin d'une story.
enum StoryNavigation: Equatable, Sendable {
    // Autre story du même compte.
    case story(Int)
    // Compte suivant ou précédent de la rangée (ses stories restent à charger).
    case author(Int)
    case close

    // Toucher à droite ou fin de la story : la suivante, sinon le compte suivant, sinon fermer.
    static func next(from position: StoryPosition, storiesCount: Int, authorsCount: Int) -> StoryNavigation {
        if position.story + 1 < storiesCount { return .story(position.story + 1) }
        if position.author + 1 < authorsCount { return .author(position.author + 1) }
        return .close
    }

    // Toucher à gauche : la précédente, sinon le compte précédent, sinon recommencer la première.
    static func previous(from position: StoryPosition) -> StoryNavigation {
        if position.story > 0 { return .story(position.story - 1) }
        if position.author > 0 { return .author(position.author - 1) }
        return .story(0)
    }
}
