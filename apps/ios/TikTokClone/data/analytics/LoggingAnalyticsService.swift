import Foundation
import os

// Sans jeton PostHog (développement) : les événements sont journalisés dans la console, rien n'est envoyé.
// Aucun feature flag n'est connu : tout le monde est dans le témoin des expériences, sauf variante forcée dans le
// build Debug (ADR-077 : `-experiment.<flag> <variante>` ou écran « Expériences », `UserDefaultsExperimentOverrides`).
@MainActor
final class LoggingAnalyticsService: AnalyticsService {
    private let logger = Logger(subsystem: "com.sachabouk.tiktokclone", category: "analytics")
    private var isStarted = false

    func start() {
        isStarted = true
        logger.info("Mesure d'audience activée (journal seulement, pas de jeton PostHog)")
    }

    func stop() {
        isStarted = false
        logger.info("Mesure d'audience désactivée")
    }

    func track(_ event: AnalyticsEvent) {
        guard isStarted else { return }
        let properties = event.properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.logDescription)" }.joined(separator: " ")
        logger.info("\(event.name, privacy: .public) \(properties, privacy: .public)")
    }

    func identify(userID: String) {
        guard isStarted else { return }
        logger.info("identify \(userID, privacy: .public)")
    }

    func reset() {
        guard isStarted else { return }
        logger.info("reset")
    }

    func variant(of flag: String) -> String? {
        guard isStarted else { return nil }
        logger.info("feature flag \(flag, privacy: .public) inconnu (pas de PostHog)")
        return nil
    }
}

extension AnalyticsValue {
    fileprivate var logDescription: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): String(value)
        }
    }
}
