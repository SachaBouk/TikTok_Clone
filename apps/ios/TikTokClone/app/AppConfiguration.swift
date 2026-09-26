import Foundation

// Configuration lue dans Info.plist, renseigné par Config/Debug.xcconfig ou Release.xcconfig.
struct AppConfiguration: Sendable {
    let apiBaseURL: URL

    // WebSocket du temps réel (ADR-011), sur le même hôte que l'API : ws:// en HTTP, wss:// en HTTPS.
    var realtimeURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = path + "/realtime"
        return components.url ?? apiBaseURL
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        guard let value = bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String, let url = URL(string: value) else {
            fatalError("APIBaseURL manquant ou invalide dans Info.plist : voir Config/*.xcconfig.")
        }
        return AppConfiguration(apiBaseURL: url)
    }
}
