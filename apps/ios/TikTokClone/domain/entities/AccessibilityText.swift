import Foundation

// Phrases lues par VoiceOver (ADR-076) : règles pures, testées sans SwiftUI. Les écrans les posent en libellés, valeurs
// et annonces ; une personne aveugle doit entendre en une phrase ce que les autres voient d'un coup d'œil.
enum SpokenText {
    private static let locale = Locale(identifier: "fr_FR")

    /// Nombre lu en entier (« 1 200 ») : les nombres compacts de l'écran (« 1,2 k ») sont lus tels quels par VoiceOver.
    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// « 1 abonné », « 1 200 abonnés » (singulier pour 0 et 1, comme en français).
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(number(value)) \(abs(value) <= 1 ? singular : plural)"
    }

    /// Durée parlée : « 4,5 secondes », « 1 seconde », « 1 minute 5 secondes », « 3 minutes ».
    static func duration(_ seconds: Double) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 {
            let rounded = (seconds * 10).rounded() / 10
            let text =
                rounded == rounded.rounded()
                ? number(Int(rounded))
                : rounded.formatted(.number.locale(locale).precision(.fractionLength(1)))
            return "\(text) \(rounded < 2 ? "seconde" : "secondes")"
        }
        let total = Int(seconds.rounded())
        let minutes = count(total / 60, "minute", "minutes")
        let rest = total % 60
        return rest == 0 ? minutes : "\(minutes) \(count(rest, "seconde", "secondes"))"
    }

    /// Position dans une vidéo : « 5 secondes sur 24 secondes ».
    static func position(_ current: Double, of total: Double) -> String {
        "\(duration(current)) sur \(duration(total))"
    }

    /// « 2 sur 5 ».
    static func ordinal(_ index: Int, of total: Int) -> String {
        "\(index + 1) sur \(total)"
    }

    /// Phrase assemblée : morceaux vides ignorés, séparés par une virgule (VoiceOver y fait une pause).
    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// Ce qui est dit d'une vidéo du feed (ADR-076) : l'état d'abord, puis le contenu.
struct VideoSpeech: Equatable {
    var author: String
    var description: String?
    var altText: String?
    var autoDescription: String?
    var locationName: String?
    var aiGenerated = false
    var isPrivate = false

    /// Libellé de l'élément « vidéo ».
    var label: String { "Vidéo de @\(author)" }

    /// Valeur lue après le libellé : état de lecture puis contenu. Le texte alternatif de l'auteur fait foi ; la
    /// description automatique ne sert que sans lui.
    func value(isPlaying: Bool, speed: Double = 1) -> String {
        let state = isPlaying ? (speed == 1 ? "En lecture" : "En lecture, vitesse \(SpeedSpeech.text(speed))") : "En pause"
        return SpokenText.join([
            state,
            isPrivate ? "Toi uniquement" : nil,
            description,
            altText.map { "Description de la vidéo : \($0)" },
            altText == nil ? autoDescription : nil,
            locationName.map { "Lieu : \($0)" },
            aiGenerated ? "Créé avec l'IA" : nil,
        ])
    }

    /// Annoncé à l'arrivée sur la vidéo : « @pseudo : description ».
    var arrival: String {
        let text = SpokenText.join([description, altText ?? autoDescription])
        return text.isEmpty ? "Vidéo de @\(author)" : "@\(author) : \(text)"
    }
}

enum SpeedSpeech {
    /// « 2 fois », « 0,5 fois », « 1,5 fois ».
    static func text(_ speed: Double) -> String {
        let value =
            speed == speed.rounded()
            ? SpokenText.number(Int(speed))
            : speed.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(1)))
        return "\(value) fois"
    }
}

// Bulle d'un message (ADR-076) : qui, quoi, quand, en une phrase.
enum MessageSpeech {
    /// « Toi : salut, 14:32 » / « Inès : salut, hier, 09:05 ».
    static func label(sender: String?, isOwn: Bool, content: String, sentAt: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let who = isOwn ? "Toi" : (sender ?? "Message")
        return SpokenText.join(["\(who) : \(content)", time(sentAt, now: now, calendar: calendar)])
    }

    /// Heure parlée d'un message : l'heure seule aujourd'hui, « hier, 09:05 », puis la date.
    static func time(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        // Heure sur deux chiffres (« 09:05 »), quelle que soit la version du format court du système.
        var style = Date.FormatStyle(locale: Locale(identifier: "fr_FR"), calendar: calendar).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = calendar.timeZone
        let hour = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) { return hour }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "hier, \(hour)"
        }
        var day = Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "fr_FR"), calendar: calendar)
        day.timeZone = calendar.timeZone
        return "\(date.formatted(day)), \(hour)"
    }
}

// Description automatique d'une image (ADR-076), faite sur l'iPhone quand l'auteur n'a pas écrit de texte alternatif.
struct ImageAnalysis: Equatable, Sendable {
    var faces: Int
    /// Identifiants de scène de Vision (`VNClassifyImageRequest`), du plus sûr au moins sûr.
    var sceneIdentifiers: [String]
    /// Texte lu dans l'image, s'il y en a.
    var recognizedText: String?
}

enum AutoDescription {
    /// Étiquettes de scène gardées au plus.
    static let maxScenes = 3
    /// Texte incrusté lu au plus (en caractères).
    static let maxTextLength = 120

    /// « Description automatique : peut contenir 2 personnes, plage, chien. Texte : « Soldes ». » ; nil s'il n'y a rien
    /// à dire. Préfixée pour qu'on ne la prenne pas pour celle de l'auteur.
    static func text(_ analysis: ImageAnalysis) -> String? {
        var things: [String] = []
        switch analysis.faces {
        case 0: break
        case 1: things.append("une personne")
        default: things.append(SpokenText.count(analysis.faces, "personne", "personnes"))
        }
        var seen = Set<String>()
        for identifier in analysis.sceneIdentifiers {
            guard let label = SceneLabels.french[identifier], seen.insert(label).inserted else { continue }
            // Une personne déjà comptée par ses visages n'est pas redite.
            if analysis.faces > 0, SceneLabels.people.contains(identifier) { continue }
            things.append(label)
            if things.count - (analysis.faces > 0 ? 1 : 0) >= maxScenes { break }
        }
        let text = analysis.recognizedText?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !things.isEmpty { parts.append("peut contenir \(things.joined(separator: ", "))") }
        if let text, !text.isEmpty {
            let short = text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "…" : text
            parts.append("texte : « \(short) »")
        }
        guard !parts.isEmpty else { return nil }
        return "Description automatique : " + parts.joined(separator: ". ")
    }
}

// Étiquettes de scène de Vision traduites en français (ADR-076). Les autres sont ignorées : mieux vaut ne rien dire
// qu'un mot anglais. Liste courte des scènes les plus fréquentes dans des vidéos verticales.
enum SceneLabels {
    static let people: Set<String> = ["people", "adult", "child", "baby", "crowd", "portrait", "selfie", "teen", "person"]

    static let french: [String: String] = [
        // Personnes
        "people": "des personnes", "adult": "un adulte", "child": "un enfant", "baby": "un bébé", "crowd": "une foule",
        "portrait": "un portrait", "selfie": "un selfie", "teen": "un adolescent", "person": "une personne",
        // Animaux
        "animal": "un animal", "dog": "un chien", "puppy": "un chiot", "cat": "un chat", "kitten": "un chaton",
        "bird": "un oiseau", "horse": "un cheval", "fish": "un poisson", "rabbit": "un lapin", "cow": "une vache",
        "insect": "un insecte", "butterfly": "un papillon", "hamster": "un hamster", "duck": "un canard",
        // Nature et lieux
        "beach": "une plage", "sea": "la mer", "ocean": "l'océan", "lake": "un lac", "river": "une rivière",
        "mountain": "une montagne", "forest": "une forêt", "tree": "un arbre", "flower": "une fleur", "garden": "un jardin",
        "grass": "de l'herbe", "sky": "le ciel", "cloudy": "un ciel nuageux", "sunset_sunrise": "un coucher de soleil",
        "snow": "de la neige", "desert": "un désert", "waterfall": "une cascade", "park": "un parc", "field": "un champ",
        "outdoor": "l'extérieur", "night_sky": "un ciel de nuit", "rainbow": "un arc-en-ciel", "water": "de l'eau",
        "city": "une ville", "street": "une rue", "building": "un bâtiment", "bridge": "un pont", "house": "une maison",
        "road": "une route", "skyscraper": "un gratte-ciel", "interior_room": "une pièce", "kitchen": "une cuisine",
        "bedroom": "une chambre", "living_room": "un salon", "bathroom": "une salle de bain", "office": "un bureau",
        "restaurant": "un restaurant", "classroom": "une salle de classe", "stadium": "un stade", "stage": "une scène",
        "concert": "un concert", "pool": "une piscine", "swimming_pool": "une piscine", "shop": "un magasin",
        // Objets et activités
        "food": "de la nourriture", "dessert": "un dessert", "cake": "un gâteau", "pizza": "une pizza",
        "burger": "un burger", "salad": "une salade", "fruit": "des fruits", "drink": "une boisson", "coffee": "un café",
        "bread": "du pain", "pasta": "des pâtes", "sushi": "des sushis", "ice_cream": "une glace", "meal": "un repas",
        "car": "une voiture", "bicycle": "un vélo", "motorcycle": "une moto", "bus": "un bus", "train": "un train",
        "airplane": "un avion", "boat": "un bateau", "vehicle": "un véhicule",
        "computer": "un ordinateur", "phone": "un téléphone", "screenshot": "une capture d'écran", "television": "une télévision",
        "book": "un livre", "document": "un document", "text": "du texte", "sign": "un panneau", "art": "une œuvre d'art",
        "painting": "une peinture", "drawing": "un dessin", "toy": "un jouet", "clothing": "des vêtements",
        "shoes": "des chaussures", "music": "de la musique", "musical_instrument": "un instrument de musique",
        "guitar": "une guitare", "piano": "un piano", "sport": "du sport", "ball": "un ballon", "soccer": "du football",
        "basketball": "du basket", "dance": "de la danse", "fireworks": "des feux d'artifice", "party": "une fête",
        "christmas_tree": "un sapin de Noël", "candle": "une bougie", "furniture": "des meubles", "table": "une table",
        "chair": "une chaise", "sofa": "un canapé", "bed": "un lit", "window": "une fenêtre", "mirror": "un miroir",
        "makeup": "du maquillage", "game": "un jeu",
    ]
}

// Texte alternatif d'une vidéo (ADR-076), mêmes règles que l'API : espaces réduits, vide = retiré, 300 caractères.
enum AltTextRules {
    static let maxLength = 300

    static func cleaned(_ text: String?) -> String? {
        let cleaned = (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }

    static func isTooLong(_ text: String) -> Bool {
        (cleaned(text) ?? "").count > maxLength
    }
}
