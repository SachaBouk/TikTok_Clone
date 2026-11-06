import Foundation

// Configuration lue dans Info.plist, renseigné par Config/Debug.xcconfig ou Release.xcconfig.
struct AppConfiguration: Sendable {
    // PostHog (ADR-013) : jeton du projet et hôte d'ingestion.
    struct Analytics: Equatable, Sendable {
        let projectToken: String
        let host: String
    }

    let apiBaseURL: URL
    // Nil sans jeton : les événements sont seulement journalisés.
    var analytics: Analytics?
    // Clé publique du SDK RevenueCat (ADR-009) ; nil : achats indisponibles.
    var revenueCatAPIKey: String?
    // Clé d'environnement de Mux Data (ADR-074) ; nil : qualité de lecture non mesurée.
    var muxDataEnvironmentKey: String?
    // Serveur du Live commun d'echimine (ADR-079).
    var liveSDKServerURL = URL(string: "https://live.echimine.fr")!

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
        let token = (bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let host = (bundle.object(forInfoDictionaryKey: "PostHogHost") as? String) ?? ""
        let revenueCatKey = (bundle.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let muxDataKey = (bundle.object(forInfoDictionaryKey: "MuxDataEnvironmentKey") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        var configuration = AppConfiguration(
            apiBaseURL: url,
            analytics: token.isEmpty ? nil : Analytics(projectToken: token, host: host),
            revenueCatAPIKey: revenueCatKey.isEmpty ? nil : revenueCatKey,
            muxDataEnvironmentKey: muxDataKey.isEmpty ? nil : muxDataKey
        )
        if let live = bundle.object(forInfoDictionaryKey: "LiveSDKServerURL") as? String, let liveURL = URL(string: live), liveURL.host() != nil {
            configuration.liveSDKServerURL = liveURL
        }
        return configuration
    }
}
