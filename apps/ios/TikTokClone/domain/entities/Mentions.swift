import Foundation

// Mentions dans un commentaire (ADR-060) : « @pseudo », ni précédé d'une lettre, d'un chiffre, de « _ », « . » ou « @ ».
// Même règle que l'API (`interactions/domain/mentions.ts`), qui prévient les comptes cités.
enum MentionRules {
    // Expressions ICU (NSRegularExpression) : les `Regex` de Swift ne savent pas regarder en arrière.
    nonisolated(unsafe) private static let pattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.@])@([A-Za-z0-9._]{2,24})"#)
    // Mention en cours de saisie, à la fin du texte (« Regarde @in ») ; « @ » seul compris.
    nonisolated(unsafe) private static let typing = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.@])@([A-Za-z0-9._]{0,24})$"#)

    struct Occurrence: Equatable {
        let range: Range<String.Index>
        let username: String
    }

    // Mentions d'un texte, avec leur place pour les rendre cliquables. Un point final ne fait pas partie du pseudo.
    static func occurrences(in text: String) -> [Occurrence] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let raw = String(text[nameRange])
            let trimmed = raw.replacing(/\.+$/, with: "")
            guard trimmed.count >= 2, let start = Range(match.range, in: text)?.lowerBound else { return nil }
            let end = text.index(nameRange.lowerBound, offsetBy: trimmed.count)
            return Occurrence(range: start..<end, username: trimmed.lowercased())
        }
    }

    // Début de pseudo tapé à la fin du texte (suggestions) : « Regarde @In » → « in » ; « @ » seul → « ».
    static func typedPrefix(in text: String) -> String? {
        guard let match = typing.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range]).lowercased()
    }

    // Remplace la mention en cours de saisie par « @pseudo », suivie d'une espace.
    static func completing(_ text: String, with username: String) -> String {
        guard let match = typing.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else { return text }
        return text.replacingCharacters(in: range, with: "@\(username) ")
    }

    // Bouton « @ » : commence une mention à la fin du texte (avec une espace avant si besoin).
    static func startingMention(in text: String) -> String {
        if typedPrefix(in: text) != nil { return text }
        guard let last = text.last else { return "@" }
        return last.isWhitespace ? text + "@" : text + " @"
    }
}

// « Je n'aime pas » sur un commentaire (ADR-060, choix du développeur) : sur l'appareil seulement, le commentaire est
// replié chez soi. 500 commentaires retenus au plus (les plus anciens oubliés).
struct DislikedComments: Equatable, Sendable {
    static let limit = 500
    private(set) var ids: [String] = []

    init(ids: [String] = []) {
        self.ids = Array(ids.suffix(Self.limit))
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
            if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit) }
        }
    }
}
