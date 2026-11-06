import Foundation

// Live commun d'echimine (ADR-079) : salles, chat, réactions et co-hôtes sont au serveur hébergé `live.echimine.fr`,
// affichés par les écrans du SDK (`LiveSDKUI`). L'app ne garde que ses liens et la source d'ouverture.

// Lien d'app vers un live : tiktokclone://lives/<id>. Identifiant du serveur commun (lettres, chiffres, « _ », « - ») ;
// les anciens lives (ADR-053) avaient un UUID, accepté aussi.
enum LiveLink {
    static func url(for liveID: String) -> URL {
        var components = URLComponents()
        components.scheme = VideoLink.scheme
        components.host = "lives"
        components.path = "/\(liveID)"
        return components.url!
    }

    static func liveID(from url: URL) -> String? {
        guard url.scheme == VideoLink.scheme, url.host == "lives" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = parts.first, isLiveID(id) else { return nil }
        return id
    }

    static func isLiveID(_ candidate: String) -> Bool {
        !candidate.isEmpty && candidate.count <= 100
            && candidate.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

// D'où un live a été ouvert (mesure d'audience, ADR-013).
enum LiveSource: String, Equatable, Sendable {
    // Liste des lives en cours, ouverte par l'icône « LIVE » de l'accueil.
    case discover
    // Après un lancement depuis l'écran de lancement (son propre live).
    case launch
    case activity
    case message
    case link
}
