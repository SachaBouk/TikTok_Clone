import Foundation

// Carrousel de comptes suggérés dans le feed « Pour toi » (choix du développeur, comme TikTok) : une page insérée après
// la 8e vidéo, puis toutes les 30 vidéos, pour un compte connecté qui a des suggestions à voir (ADR-058).
enum SuggestionCarouselRules {
    static let firstSlot = 8
    static let interval = 30

    // Expérience « suggestion-carousel-slot » (ADR-077) : premier carrousel après la 4e vidéo en variante.
    static let earlyFirstSlot = 4

    static func firstSlot(forVariant variant: String) -> Int {
        variant == "after-4" ? earlyFirstSlot : firstSlot
    }

    // Le carrousel suit-il la `count`-ième vidéo de la session (à partir de 1) ?
    static func isSlot(afterVideo count: Int, firstSlot: Int = firstSlot) -> Bool {
        count >= firstSlot && (count - firstSlot) % interval == 0
    }

    // Carte à montrer après avoir écarté celle de `id` : la suivante, sinon la précédente.
    static func neighbor(of id: String, in ids: [String]) -> String? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        if ids.indices.contains(index + 1) { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }

    // Carte suivante, après un abonnement.
    static func next(after id: String, in ids: [String]) -> String? {
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + 1) else { return nil }
        return ids[index + 1]
    }
}

extension AccountSuggestion {
    // Raison sous le nom, sur une carte du carrousel : « hyaa8 fait partie de ses followers », « Suivi(e) par mny8,
    // mny8881 et 1 autre utilisateur(trice) », « Fait partie de tes followers », ou une suggestion simple.
    var carouselReason: String {
        if followsYou { return "Fait partie de tes followers" }
        let names = followedBy.prefix(2).map(\.username)
        guard let first = names.first else { return "Personnes que tu pourrais connaître" }
        if followedByCount == 1 { return "\(first) fait partie de ses followers" }
        let others = max(0, followedByCount - names.count)
        switch others {
        case 0: return "Suivi(e) par \(names.joined(separator: " et "))"
        case 1: return "Suivi(e) par \(names.joined(separator: ", ")) et 1 autre utilisateur(trice)"
        default: return "Suivi(e) par \(names.joined(separator: ", ")) et \(others) autres utilisateur(trice)s"
        }
    }
}

// Couleur du fond d'une carte, en haut de la page : tirée de la couleur moyenne de la photo, ravivée et ramenée à une
// luminosité moyenne (lisible en blanc, jamais criarde) ; sans photo, une teinte tirée du pseudo.
struct SuggestionTone: Equatable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    static let minBrightness = 0.42
    static let maxBrightness = 0.6
    // En dessous, la photo est grise : le fond reste gris.
    static let grayThreshold = 0.1

    // Composantes de 0 à 1.
    init(red: Double, green: Double, blue: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue > 0 ? delta / maxValue : 0
        self.hue = hue
        self.saturation = saturation < Self.grayThreshold ? 0 : min(1, max(0.55, saturation * 1.25))
        brightness = min(Self.maxBrightness, max(Self.minBrightness, maxValue))
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    // Sans photo : teinte stable, tirée du pseudo.
    static func fallback(for username: String) -> SuggestionTone {
        let sum = username.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return SuggestionTone(hue: Double(sum % 360) / 360, saturation: 0.6, brightness: 0.5)
    }
}
