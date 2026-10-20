import SwiftUI

// Description d'une vidéo dont les hashtags sont cliquables (ADR-049) : chacun ouvre la page du hashtag. Avec `onMention`,
// les mentions aussi (ADR-065) : chacune ouvre le profil.
// Liens internes (`tiktokclone://hashtags/<nom>`, `tiktokclone://users/<pseudo>`), interceptés par l'écran : ils ne quittent
// jamais l'app.
struct HashtagText: View {
    let text: String
    let onHashtag: (String) -> Void
    var onMention: ((String) -> Void)? = nil

    // Vrai si le texte a quelque chose à toucher (sinon il laisse passer les touchers).
    static func hasLinks(_ text: String, mentions: Bool) -> Bool {
        !HashtagRules.occurrences(in: text).isEmpty || (mentions && !MentionRules.occurrences(in: text).isEmpty)
    }

    var body: some View {
        Text(attributed)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if let onMention, let username = ProfileLink.username(from: url) {
                        onMention(username)
                        return .handled
                    }
                    guard let name = HashtagLink.name(from: url) else { return .discarded }
                    onHashtag(name)
                    return .handled
                })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        if onMention != nil {
            for occurrence in MentionRules.occurrences(in: text) {
                guard let range = Range(occurrence.range, in: result) else { continue }
                result[range].link = ProfileLink.url(for: occurrence.username)
                result[range].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        for occurrence in HashtagRules.occurrences(in: text) {
            guard let range = Range(occurrence.range, in: result) else { continue }
            result[range].link = HashtagLink.url(for: occurrence.name)
            result[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}

enum HashtagLink {
    static func url(for name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "tiktokclone"
        components.host = "hashtags"
        components.path = "/\(name)"
        return components.url
    }

    static func name(from url: URL) -> String? {
        guard url.scheme == "tiktokclone", url.host() == "hashtags" else { return nil }
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
