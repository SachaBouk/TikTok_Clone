import CoreGraphics
import Foundation

// Phrases lues par VoiceOver dans la création (ADR-076, « Création et éditeur complet ») et équivalents des gestes de
// l'éditeur (déplacer, agrandir, recadrer au doigt) : règles pures, testées sans SwiftUI.

// « Description pour l'accessibilité » de l'écran de publication.
enum AltTextSpeech {
    static let explanation = "Lue par VoiceOver aux personnes aveugles ou malvoyantes."

    /// « 280 caractères restants », « 1 caractère en trop ».
    static func remaining(_ count: Int) -> String {
        count >= 0
            ? SpokenText.count(count, "caractère restant", "caractères restants")
            : SpokenText.count(-count, "caractère en trop", "caractères en trop")
    }

    /// Sous-titre de la ligne de l'écran de publication : le texte écrit, sinon l'explication.
    static func summary(_ text: String) -> String {
        AltTextRules.cleaned(text) ?? explanation
    }
}

// Caméra : déclencheur, segments filmés, minuteur.
enum CameraSpeech {
    /// Durée proposée, lue en entier : « 3 minutes », « 60 secondes ».
    static func limit(_ limit: RecordingLimit) -> String {
        SpokenText.duration(limit.duration.seconds)
    }

    /// Valeur du déclencheur : « 12 secondes filmées sur 3 minutes ».
    static func recorded(_ recorded: Duration, of maximum: Duration) -> String {
        "\(SpokenText.duration(recorded.seconds)) filmées sur \(SpokenText.duration(maximum.seconds))"
    }

    /// Annoncé au début d'un segment : « Enregistrement, 2 minutes 48 secondes restantes ».
    static func started(remaining: Duration) -> String {
        "Enregistrement, \(SpokenText.duration(remaining.seconds)) restantes"
    }

    /// Annoncé à l'arrêt d'un segment : « Segment de 4 secondes filmé, 12 secondes au total ».
    static func segmentRecorded(_ segment: Duration, total: Duration) -> String {
        "Segment de \(SpokenText.duration(segment.seconds)) filmé, \(SpokenText.duration(total.seconds)) au total"
    }

    /// Annoncé quand le dernier segment est retiré : « Dernier segment supprimé, 8 secondes filmées » ; « Aucun segment ».
    static func segmentRemoved(total: Duration) -> String {
        total > .zero ? "Dernier segment supprimé, \(SpokenText.duration(total.seconds)) filmées" : "Dernier segment supprimé, aucun segment"
    }

    /// Compte à rebours du minuteur : « 3 », puis « 2 »…
    static func countdown(_ remaining: Int) -> String { SpokenText.number(remaining) }
}

// Galerie maison.
enum GallerySpeech {
    private static let locale = Locale(identifier: "fr_FR")

    /// « Vidéo, 12 secondes, 3 mai » ; « Photo, 3 mai 2024 » (l'année seulement si elle diffère).
    static func label(isVideo: Bool, duration: Duration?, date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        SpokenText.join([
            isVideo ? "Vidéo" : "Photo",
            isVideo ? duration.map { SpokenText.duration($0.seconds) } : nil,
            date.map { day($0, now: now, calendar: calendar) },
        ])
    }

    /// « Sélectionnée, numéro 2 » ; vide si elle ne l'est pas.
    static func value(number: Int?) -> String {
        number.map { "Sélectionnée, numéro \($0)" } ?? ""
    }

    /// Annoncé à chaque choix : « 2 vidéos sélectionnées » ; « Aucune vidéo sélectionnée ».
    static func selection(_ count: Int) -> String {
        count == 0 ? "Aucune vidéo sélectionnée" : SpokenText.count(count, "vidéo sélectionnée", "vidéos sélectionnées")
    }

    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.wide)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

// Éditeur par clips.
enum ClipSpeech {
    /// Pas des poignées de début et de fin (actions ajustables).
    static let trimStep: Duration = .milliseconds(100)
    /// Pas de la tête de lecture.
    static let playheadStep: Duration = .milliseconds(500)

    /// « Clip 2 sur 3, 4,5 secondes, vitesse 1,5 fois, son coupé ».
    static func label(index: Int, count: Int, duration: Duration, speed: Double, volume: Double, muted: Bool) -> String {
        SpokenText.join([
            "Clip \(SpokenText.ordinal(index, of: count))",
            SpokenText.duration(duration.seconds),
            speed != 1 ? "vitesse \(SpeedSpeech.text(speed))" : nil,
            muted || volume == 0 ? "son coupé" : (volume < 1 ? "volume \(Int((volume * 100).rounded())) %" : nil),
        ])
    }

    /// Valeur d'une poignée : position dans le fichier d'origine, « 1,2 seconde sur 8 secondes de la vidéo d'origine ».
    static func handle(_ time: Duration, of source: Duration) -> String {
        "\(SpokenText.position(time.seconds, of: source.seconds)) de la vidéo d'origine"
    }

    /// Tête de lecture déplacée d'un pas, sans sortir de la vidéo.
    static func playhead(_ time: Duration, increment: Bool, total: Duration) -> Duration {
        let moved = increment ? time + playheadStep : time - playheadStep
        return min(max(moved, .zero), total)
    }
}

// Vitesse et volume des panneaux de l'éditeur par clips.
enum EditorValueSpeech {
    /// « 1,5 fois ».
    static func speed(_ speed: Double) -> String { SpeedSpeech.text(speed) }

    /// « 80 % ».
    static func percent(_ value: Double) -> String { "\(Int((min(max(value, 0), 1) * 100).rounded())) %" }
}

// Position d'un élément posé sur l'image (texte, autocollant, cadre), en mots.
enum PlacementSpeech {
    /// « au centre », « en haut à gauche », « au milieu à droite », « en bas au centre ».
    static func region(_ point: CGPoint) -> String {
        let vertical = point.y < 0.35 ? "en haut" : (point.y > 0.65 ? "en bas" : nil)
        let horizontal = point.x < 0.35 ? "à gauche" : (point.x > 0.65 ? "à droite" : nil)
        switch (vertical, horizontal) {
        case (nil, nil): return "au centre"
        case (nil, let horizontal?): return "au milieu \(horizontal)"
        case (let vertical?, nil): return "\(vertical) au centre"
        case (let vertical?, let horizontal?): return "\(vertical) \(horizontal)"
        }
    }
}

// Textes et autocollants posés : équivalents du glisser, du pincer et de la corbeille.
enum OverlaySpeech {
    enum Direction: CaseIterable, Sendable {
        case up, down, left, right

        var title: String {
            switch self {
            case .up: "Déplacer vers le haut"
            case .down: "Déplacer vers le bas"
            case .left: "Déplacer vers la gauche"
            case .right: "Déplacer vers la droite"
            }
        }
    }

    /// Pas d'un déplacement : 5 % de l'image.
    static let moveStep = 0.05
    /// Facteur de « Agrandir » (et son inverse pour « Réduire »).
    static let scaleStep = 1.25

    /// « Texte : Bonjour ».
    static func textLabel(_ text: String) -> String { "Texte : \(text)" }

    /// « Autocollant : 🔥 », « Autocollant : Heure 16:42 ».
    static func stickerLabel(kind: String?, text: String) -> String {
        "Autocollant : \(kind.map { "\($0) \(text)" } ?? text)"
    }

    /// Valeur : « en haut à gauche, taille 125 % ».
    static func value(center: CGPoint, scale: Double) -> String {
        "\(PlacementSpeech.region(center)), taille \(Int((scale * 100).rounded())) %"
    }

    /// Centre déplacé d'un pas, gardé dans l'image avec la marge du plan (5 %, comme `moveText` / `moveSticker`).
    static func moved(_ center: CGPoint, _ direction: Direction) -> CGPoint {
        let moved: CGPoint =
            switch direction {
            case .up: CGPoint(x: center.x, y: center.y - moveStep)
            case .down: CGPoint(x: center.x, y: center.y + moveStep)
            case .left: CGPoint(x: center.x - moveStep, y: center.y)
            case .right: CGPoint(x: center.x + moveStep, y: center.y)
            }
        return CGPoint(x: min(max(moved.x, 0.05), 0.95), y: min(max(moved.y, 0.05), 0.95))
    }

    /// Échelle agrandie ou réduite d'un pas, dans `range`.
    static func scaled(_ scale: Double, larger: Bool, range: ClosedRange<Double>) -> Double {
        min(max(larger ? scale * scaleStep : scale / scaleStep, range.lowerBound), range.upperBound)
    }
}

// Recadrage : cadre décrit en mots et déplacé ou agrandi par actions.
enum CropSpeech {
    /// Pas d'un déplacement : 5 % de l'image.
    static let moveStep = 0.05
    /// Facteur de « Agrandir » (et son inverse pour « Réduire »).
    static let scaleStep = 1.15

    /// Proportions lues : « libres », « 9:16 ».
    static func ratio(_ ratio: CropRatio) -> String { ratio == .free ? "libres" : ratio.title }

    /// « Image entière » ; « Cadre 1:1, centré, 56 % de la largeur, 100 % de la hauteur » ; « Cadre libre, en haut à gauche, … ».
    static func value(_ rect: CropRect, ratio: CropRatio) -> String {
        guard !rect.isFull else { return "Image entière" }
        let center = CGPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
        let region = PlacementSpeech.region(center)
        return SpokenText.join([
            ratio == .free ? "Cadre libre" : "Cadre \(ratio.title)",
            region == "au centre" ? "centré" : region,
            "\(percent(rect.width)) de la largeur",
            "\(percent(rect.height)) de la hauteur",
        ])
    }

    /// Cadre déplacé d'un pas, sans sortir de l'image.
    static func moved(_ rect: CropRect, _ direction: OverlaySpeech.Direction) -> CropRect {
        switch direction {
        case .up: CropRules.moved(rect, dx: 0, dy: -moveStep)
        case .down: CropRules.moved(rect, dx: 0, dy: moveStep)
        case .left: CropRules.moved(rect, dx: -moveStep, dy: 0)
        case .right: CropRules.moved(rect, dx: moveStep, dy: 0)
        }
    }

    /// Cadre agrandi ou réduit autour de son centre, proportions gardées, jamais hors de l'image ni sous le côté minimal.
    static func scaled(_ rect: CropRect, larger: Bool, ratio: CropRatio, frameAspect: Double) -> CropRect {
        let factor = larger ? scaleStep : 1 / scaleStep
        var width = rect.width * factor
        var height = rect.height * factor
        if let value = ratio.value, frameAspect > 0 {
            let relative = value / frameAspect
            width = min(width, 1, relative)
            height = width / relative
            if height > 1 {
                height = 1
                width = relative
            }
            if min(width, height) < CropRules.minSize {
                let grow = CropRules.minSize / min(width, height)
                width *= grow
                height *= grow
            }
        } else {
            width = min(max(width, CropRules.minSize), 1)
            height = min(max(height, CropRules.minSize), 1)
        }
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2
        let centered = CropRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        // Ramené dans l'image s'il en dépasse.
        return CropRules.moved(centered, dx: 0, dy: 0)
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}

// Plages d'effets et voix off.
enum TimelineSpeech {
    /// Pas des actions sur une plage d'effet.
    static let effectStep: Duration = .milliseconds(500)

    /// « Négatif, de 2 secondes à 4 secondes ».
    static func range(_ title: String, start: Duration, end: Duration) -> String {
        "\(title), de \(SpokenText.duration(start.seconds)) à \(SpokenText.duration(end.seconds))"
    }

    /// « Effet Négatif posé, de 2 secondes à 4 secondes ».
    static func effectAdded(_ title: String, start: Duration, end: Duration) -> String {
        "Effet \(range(title, start: start, end: end)) posé"
    }

    /// « Voix off enregistrée, 3,2 secondes ».
    static func voiceoverRecorded(_ duration: Duration) -> String {
        "Voix off enregistrée, \(SpokenText.duration(duration.seconds))"
    }

    /// « Enregistrement de la voix off à partir de 5 secondes ».
    static func voiceoverStarted(at start: Duration) -> String {
        "Enregistrement de la voix off à partir de \(SpokenText.duration(start.seconds))"
    }
}

// Couverture : image choisie parmi les dix de la frise.
enum CoverSpeech {
    /// Rang (0 à `count` - 1) de l'image la plus proche de `time`.
    static func index(of time: Duration, duration: Duration, count: Int = CoverChoice.frameCount) -> Int {
        guard duration > .zero, count > 0 else { return 0 }
        return min(max(Int((time / duration * Double(count) + 1e-6).rounded(.down)), 0), count - 1)
    }

    /// « Image 3 sur 10, à 12 secondes ».
    static func value(time: Duration, duration: Duration, count: Int = CoverChoice.frameCount) -> String {
        "Image \(SpokenText.ordinal(index(of: time, duration: duration, count: count), of: count)), à \(SpokenText.duration(time.seconds))"
    }
}

// Brouillons et sons.
enum DraftSpeech {
    /// « Brouillon, 12 secondes, Ma description ».
    static func label(description: String, duration: Duration) -> String {
        SpokenText.join(["Brouillon", SpokenText.duration(duration.seconds), description])
    }
}

enum SoundSpeech {
    /// « Son original - @ines, Inès, 3 publications, 12 secondes ».
    static func label(title: String, author: String, uses: Int, duration: Duration) -> String {
        SpokenText.join([title, author, SpokenText.count(uses, "publication", "publications"), SpokenText.duration(duration.seconds)])
    }
}
