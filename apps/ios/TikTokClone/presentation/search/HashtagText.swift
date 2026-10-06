import SwiftUI

// Description d'une vidéo dont les hashtags sont cliquables (ADR-049) : chacun ouvre la page du hashtag.
// Liens internes (`tiktokclone://hashtags/<nom>`), interceptés par l'écran : ils ne quittent jamais l'app.
struct HashtagText: View {
    let text: String
    let onHashtag: (String) -> Void

    var body: some View {
        Text(attributed)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let name = HashtagLink.name(from: url) else { return .discarded }
                    onHashtag(name)
                    return .handled
                })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
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
