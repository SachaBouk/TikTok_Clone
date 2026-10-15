import Foundation

// Profil d'un compte (ADR-016 : nom, pseudo, photo, bio, abonnés, abonnements ; likes reçus, ADR-056).
// Entité du domaine : ne dépend ni du client généré ni de l'API (ADR-002).
struct UserProfile: Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let bio: String?
    let followersCount: Int
    let followingCount: Int
    let createdAt: Date
    // Likes reçus sur ses vidéos publiées (compteur « J'aime », ADR-056).
    var likesCount = 0
}

// Lien d'app vers un profil (« Partager le profil », ADR-056) : tiktokclone://users/<pseudo>.
enum ProfileLink {
    static func url(for username: String) -> URL {
        var components = URLComponents()
        components.scheme = VideoLink.scheme
        components.host = "users"
        components.path = "/\(username)"
        return components.url!
    }

    // Pseudo du profil, ou nil si le lien n'est pas un lien de profil valide.
    static func username(from url: URL) -> String? {
        guard url.scheme == VideoLink.scheme, url.host == "users" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let username = parts.first?.lowercased(), username.wholeMatch(of: RegistrationRules.usernamePattern) != nil else {
            return nil
        }
        return username
    }
}

// Recadrage rond de la photo de profil (ADR-056) : l'image remplit le cercle (`side` points), puis se déplace et
// s'agrandit au doigt sans jamais laisser de vide dans le cercle. Règles pures, testées sans UIKit.
struct AvatarCrop: Equatable, Sendable {
    static let maxZoom: CGFloat = 5

    let imageSize: CGSize
    let side: CGFloat
    private(set) var zoom: CGFloat = 1
    // Déplacement du centre de l'image par rapport au centre du cercle, en points.
    private(set) var offset: CGSize = .zero

    init(imageSize: CGSize, side: CGFloat) {
        self.imageSize = imageSize
        self.side = side
    }

    // Points affichés par pixel de l'image.
    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return side / min(imageSize.width, imageSize.height) * zoom
    }

    var displayedSize: CGSize { CGSize(width: imageSize.width * scale, height: imageSize.height * scale) }

    // Nouveau zoom et nouveau déplacement, ramenés dans les limites.
    func with(zoom: CGFloat, offset: CGSize) -> AvatarCrop {
        var crop = self
        crop.zoom = min(Self.maxZoom, max(1, zoom))
        let size = crop.displayedSize
        let maxX = max(0, (size.width - side) / 2)
        let maxY = max(0, (size.height - side) / 2)
        crop.offset = CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
        return crop
    }

    // Carré de l'image (en pixels) visible dans le cercle.
    var cropRect: CGRect {
        let length = side / scale
        let centerX = imageSize.width / 2 - offset.width / scale
        let centerY = imageSize.height / 2 - offset.height / scale
        return CGRect(x: centerX - length / 2, y: centerY - length / 2, width: length, height: length)
    }
}
