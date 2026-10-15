import Foundation
import Synchronization

@testable import TikTokClone

// Mesure d'audience simulée : enregistre ce qui serait envoyé à PostHog, si le service a été démarré.
@MainActor
final class FakeAnalyticsService: AnalyticsService {
    private(set) var isStarted = false
    private(set) var events: [AnalyticsEvent] = []
    private(set) var identified: [String] = []
    private(set) var resetCount = 0
    private(set) var flagReads: [String] = []
    var flags: [String: String] = [:]

    var eventNames: [String] { events.map(\.name) }

    func start() { isStarted = true }
    func stop() { isStarted = false }

    func track(_ event: AnalyticsEvent) {
        guard isStarted else { return }
        events.append(event)
    }

    func identify(userID: String) {
        guard isStarted else { return }
        identified.append(userID)
    }

    func reset() {
        guard isStarted else { return }
        resetCount += 1
    }

    func variant(of flag: String) -> String? {
        guard isStarted else { return nil }
        flagReads.append(flag)
        return flags[flag]
    }
}

final class InMemoryPreferencesStore: PreferencesStore {
    private let state: Mutex<(consent: Bool?, guestPromptDecided: Bool, onboardingCompleted: Bool, feedSwipeHintShown: Bool)>

    init(consent: Bool? = nil, onboardingCompleted: Bool = false, feedSwipeHintShown: Bool = false) {
        state = Mutex((consent, false, onboardingCompleted, feedSwipeHintShown))
    }

    var analyticsConsent: Bool? { state.withLock { $0.consent } }
    func setAnalyticsConsent(_ consent: Bool) { state.withLock { $0.consent = consent } }
    var guestPromptDecided: Bool { state.withLock { $0.guestPromptDecided } }
    func markGuestPromptDecided() { state.withLock { $0.guestPromptDecided = true } }
    var onboardingCompleted: Bool { state.withLock { $0.onboardingCompleted } }
    func markOnboardingCompleted() { state.withLock { $0.onboardingCompleted = true } }
    var feedSwipeHintShown: Bool { state.withLock { $0.feedSwipeHintShown } }
    func markFeedSwipeHintShown() { state.withLock { $0.feedSwipeHintShown = true } }
}

// Mesure d'audience acceptée, avec un service simulé.
@MainActor
func makeAnalytics(
    _ service: FakeAnalyticsService = FakeAnalyticsService(), consent: Bool? = true,
    preferences: InMemoryPreferencesStore? = nil
) -> AnalyticsModel {
    AnalyticsModel(service: service, preferences: preferences ?? InMemoryPreferencesStore(consent: consent))
}
