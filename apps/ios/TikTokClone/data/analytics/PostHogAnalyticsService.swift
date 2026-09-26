import Foundation
import PostHog

// Mesure d'audience et tests A/B par PostHog (ADR-013), hébergé dans l'UE (PostHog Cloud UE ; hôte configurable
// pour un PostHog auto-hébergé, ADR-015).
// - Le SDK n'est initialisé qu'au `start` : sans consentement, aucune requête n'est faite (le SDK charge ses
//   feature flags dès l'initialisation, ce qui envoie déjà un identifiant).
// - Retrait du consentement : le SDK est fermé (`close`), sans aucune requête ; les événements non envoyés sont
//   abandonnés. Un compte identifié le reste s'il redonne son accord (identifiant gardé par le SDK). Piège : `reset`
//   et `optOut` ne suffisent pas, `reset` recharge les feature flags (requête) même après `optOut`.
// - Événements du cycle de vie de l'app (installation, ouverture, arrière-plan) : rétention D1, D7, D30.
// - Pas d'écrans capturés automatiquement (SwiftUI), pas d'enregistrement de session.
@MainActor
final class PostHogAnalyticsService: AnalyticsService {
    private let configuration: AppConfiguration.Analytics
    private var isStarted = false

    init(configuration: AppConfiguration.Analytics) {
        self.configuration = configuration
    }

    private var sdk: PostHogSDK { PostHogSDK.shared }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.sessionReplay = false
        // Profils de personne pour les seuls comptes identifiés : les invités restent anonymes.
        config.personProfiles = .identifiedOnly
        sdk.setup(config)
        // Un refus enregistré par le SDK lui-même (`optOut`, état persistant) ne doit pas l'emporter sur le consentement.
        sdk.optIn()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        sdk.close()
    }

    func track(_ event: AnalyticsEvent) {
        guard isStarted else { return }
        sdk.capture(event.name, properties: event.properties.mapValues(\.postHogValue))
    }

    func identify(userID: String) {
        guard isStarted else { return }
        sdk.identify(userID)
    }

    func reset() {
        guard isStarted else { return }
        sdk.reset()
    }

    func variant(of flag: String) -> String? {
        guard isStarted else { return nil }
        switch sdk.getFeatureFlag(flag) {
        case let variant as String: return variant
        case let enabled as Bool: return enabled ? "true" : "false"
        default: return nil
        }
    }
}

extension AnalyticsValue {
    var postHogValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        }
    }
}
