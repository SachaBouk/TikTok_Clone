import Foundation

// Feuille « Envoyer à » d'une vidéo, comme TikTok : destinataires choisis (un ou plusieurs), message facultatif envoyé
// avec la vidéo, liste complète ouverte par la loupe (« Chats récents », « Amis », « Suivis » de A à Z) et recherche
// parmi ces comptes, sans casse ni accents.
enum ShareRecipientRules {
    // Barre d'emojis sous le message : un toucher ajoute l'emoji au texte.
    static let quickEmojis = ["🥰", "👍", "😂", "😎", "🥺", "🙏"]
    // Liste complète : les abonnements sont tous lus pour les ranger de A à Z ; au-delà, la suite n'est pas lue.
    static let maxFollowingPages = 50
    // Section des noms qui ne commencent pas par une lettre.
    static let otherSection = "#"

    // Lettre de la section d'un nom : « É » range sous « E », un chiffre ou un emoji sous « # ».
    static func section(for title: String) -> String {
        guard let first = folded(title).first, first.isLetter, first.isASCII else { return otherSection }
        return String(first).uppercased()
    }

    // Recherche : le nom ou le pseudo contient le texte (« @ » initial ignoré), sans casse ni accents.
    static func matches(_ query: String, title: String, username: String?) -> Bool {
        var needle = folded(query.trimmingCharacters(in: .whitespaces))
        if needle.hasPrefix("@") { needle.removeFirst() }
        guard !needle.isEmpty else { return true }
        return folded(title).contains(needle) || username.map { folded($0).contains(needle) } == true
    }

    // Ordre alphabétique des « Suivis » : sans casse ni accents, les noms sans lettre en dernier.
    static func precedes(_ title: String, _ other: String) -> Bool {
        let (left, right) = (section(for: title), section(for: other))
        if left != right {
            if left == otherSection || right == otherSection { return right == otherSection }
            return left < right
        }
        return folded(title).localizedStandardCompare(folded(other)) == .orderedAscending
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
    }
}
