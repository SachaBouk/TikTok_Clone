import Foundation

// Recherche de comptes et hashtags (ADR-049). Entités du domaine, indépendantes du client généré (ADR-002).

// Compte trouvé : résumé, nombre d'abonnés et relation avec le compte connecté (nil en mode invité).
struct AccountSearchResult: Identifiable, Equatable, Sendable {
    var id: String { user.id }
    let user: UserSummary
    let followersCount: Int
    let viewer: FollowViewer?
}

struct AccountSearchPage: Equatable, Sendable {
    let results: [AccountSearchResult]
    let nextCursor: String?
}

struct Hashtag: Identifiable, Hashable, Sendable {
    var id: String { name }
    // Sans « # », en minuscules.
    let name: String
    // Vidéos publiées portant ce hashtag.
    let videosCount: Int

    var title: String { "#\(name)" }

    var videosLabel: String {
        videosCount == 1 ? "1 vidéo" : "\(videosCount.formatted(.number.notation(.compactName))) vidéos"
    }
}

// Règle des hashtags, alignée sur l'API (`videos/domain/hashtags.ts`) : « # » suivi de 1 à 50 lettres, chiffres ou
// « _ », ni précédé ni suivi d'un tel caractère, au moins une lettre ou un chiffre, nom en minuscules.
enum HashtagRules {
    static let maxLength = 50

    // Expressions ICU (NSRegularExpression) : les `Regex` de Swift ne savent pas regarder en arrière.
    nonisolated(unsafe) private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{Nl}\p{Nd}_])#([\p{L}\p{Nl}\p{Nd}_]{1,50})(?![\p{L}\p{Nl}\p{Nd}_])"#)
    // Hashtag en cours de saisie, à la fin du texte (« … #pla »).
    nonisolated(unsafe) private static let typing = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{Nl}\p{Nd}_])#([\p{L}\p{Nl}\p{Nd}_]{1,50})$"#)
    nonisolated(unsafe) private static let letterOrDigit = try! NSRegularExpression(pattern: #"[\p{L}\p{Nl}\p{Nd}]"#)
    nonisolated(unsafe) private static let fullName = try! NSRegularExpression(pattern: #"^[\p{L}\p{Nl}\p{Nd}_]{1,50}$"#)

    struct Occurrence: Equatable {
        let range: Range<String.Index>
        let name: String
    }

    // Hashtags d'un texte (description), avec leur place pour les rendre cliquables.
    static func occurrences(in text: String) -> [Occurrence] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let raw = String(text[nameRange])
            guard hasLetterOrDigit(raw) else { return nil }
            return Occurrence(range: range, name: normalized(raw))
        }
    }

    // Début de hashtag tapé à la fin du texte (suggestions de la publication) : « Ma vidéo #Pla » → « pla ».
    static func typedPrefix(in text: String) -> String? {
        guard let match = typing.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return normalized(String(text[range]))
    }

    // Remplace le hashtag en cours de saisie par `name`, suivi d'une espace.
    static func completing(_ text: String, with name: String) -> String {
        guard let match = typing.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else { return text }
        return text.replacingCharacters(in: range, with: "#\(name) ")
    }

    // Texte cherché qui désigne un hashtag (« #Été » → « été ») ; nil sinon.
    static func name(fromQuery query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let name = String(trimmed.dropFirst())
        guard fullName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil, hasLetterOrDigit(name) else { return nil }
        return normalized(name)
    }

    private static func normalized(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func hasLetterOrDigit(_ text: String) -> Bool {
        letterOrDigit.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

// Historique des recherches, gardé sur l'appareil (ADR-049) : la plus récente d'abord, sans doublon (casse comprise).
struct SearchHistory: Equatable, Sendable {
    static let maxEntries = 20

    private(set) var queries: [String]

    init(_ queries: [String] = []) {
        self.queries = Array(queries.prefix(Self.maxEntries))
    }

    mutating func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queries.removeAll { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
        queries.insert(trimmed, at: 0)
        queries = Array(queries.prefix(Self.maxEntries))
    }

    mutating func remove(_ query: String) {
        queries.removeAll { $0 == query }
    }
}
