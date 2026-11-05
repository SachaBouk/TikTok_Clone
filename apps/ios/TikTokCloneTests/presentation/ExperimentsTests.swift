import Foundation
import Testing

@testable import TikTokClone

@MainActor
@Suite("Expériences A/B")
struct ExperimentsTests {
    let service = FakeAnalyticsService()
    let preferences = InMemoryPreferencesStore(consent: true)
    let overrides = InMemoryExperimentOverrides()
    let experiment = Experiments.feedSwipeHint

    private func makeModel(consent: Bool? = true) -> AnalyticsModel {
        if let consent { preferences.setAnalyticsConsent(consent) }
        return AnalyticsModel(service: service, preferences: preferences, overrides: overrides)
    }

    @Test("catalogue : clés uniques, témoin parmi les variantes")
    func catalog() {
        #expect(Set(Experiments.all.map(\.flag)).count == Experiments.all.count)
        for experiment in Experiments.all {
            #expect(experiment.isKnown(experiment.control))
            #expect(experiment.variants.count >= 2)
        }
    }

    @Test("variante de PostHog : tirée une fois, gardée, exposée une seule fois")
    func assigned() {
        service.flags[experiment.flag] = "hidden"
        let model = makeModel()
        #expect(model.decide(experiment) == ExperimentDecision(variant: "hidden", source: .assigned))
        #expect(service.events == [.experimentExposed(experiment, variant: "hidden")])
        // PostHog change d'avis (nouvel identifiant à la connexion) : le groupe tiré reste.
        service.flags[experiment.flag] = "shown"
        #expect(model.decide(experiment) == ExperimentDecision(variant: "hidden", source: .stored))
        #expect(service.eventNames == ["experiment_exposed"])
        #expect(preferences.experimentAssignments == [experiment.flag: "hidden"])
    }

    @Test("sans consentement : témoin, flag jamais lu, rien de gardé")
    func noConsent() {
        service.flags[experiment.flag] = "hidden"
        let model = makeModel(consent: false)
        #expect(model.decide(experiment) == ExperimentDecision(variant: "shown", source: .noConsent))
        #expect(service.flagReads.isEmpty)
        #expect(preferences.experimentAssignments.isEmpty)
    }

    @Test("flags pas chargés ou variante inconnue : témoin pour cette fois, réessayé ensuite")
    func unavailable() {
        let model = makeModel()
        #expect(model.decide(experiment).source == .unavailable)
        service.flags[experiment.flag] = "true"
        #expect(model.decide(experiment) == ExperimentDecision(variant: "shown", source: .unavailable))
        #expect(preferences.experimentAssignments.isEmpty)
        #expect(service.events.isEmpty)
        service.flags[experiment.flag] = "shown"
        #expect(model.decide(experiment).source == .assigned)
    }

    @Test("flags arrivés pendant l'attente : groupe tiré")
    func waitsForFlags() async {
        let model = makeModel()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            service.flags[experiment.flag] = "hidden"
        }
        let decision = await model.decideWhenLoaded(experiment, timeout: .seconds(3))
        #expect(decision == ExperimentDecision(variant: "hidden", source: .assigned))
    }

    @Test("variante forcée (Debug) : l'emporte, même sans consentement, jamais exposée ni gardée")
    func forced() {
        service.flags[experiment.flag] = "shown"
        let model = makeModel(consent: false)
        model.setForcedVariant("hidden", of: experiment)
        #expect(model.decide(experiment) == ExperimentDecision(variant: "hidden", source: .forced))
        #expect(model.forcedVariant(of: experiment) == "hidden")
        #expect(service.flagReads.isEmpty)
        #expect(preferences.experimentAssignments.isEmpty)
        // Variante forcée inconnue du catalogue : ignorée.
        model.setForcedVariant("autre", of: experiment)
        #expect(model.decide(experiment).source == .noConsent)
        model.setForcedVariant(nil, of: experiment)
        #expect(model.forcedVariant(of: experiment) == nil)
    }

    @Test("groupes oubliés : tirés de nouveau")
    func clear() {
        service.flags[experiment.flag] = "hidden"
        let model = makeModel()
        _ = model.decide(experiment)
        #expect(model.storedVariant(of: experiment) == "hidden")
        model.clearExperimentAssignments()
        #expect(model.storedVariant(of: experiment) == nil)
        #expect(model.decide(experiment).source == .assigned)
    }

    @Test("invitation invité forcée : à chaque seuil, sans être gardée")
    func forcedGuestPrompt() {
        let model = makeModel()
        model.setForcedVariant("prompt", of: Experiments.guestSignupPrompt)
        #expect(model.shouldPromptGuest())
        #expect(model.shouldPromptGuest())
        #expect(service.eventNames == ["guest_prompt_shown", "guest_prompt_shown"])
    }

    @Test("indication du feed, variante hidden : vue comme montrée, ne revient pas après une inscription")
    func hiddenSwipeHint() async {
        let onboarding = OnboardingModel(preferences: preferences)
        await onboarding.decideFeedSwipeHint { "hidden" }
        #expect(!onboarding.showsFeedSwipeHint)
        #expect(!onboarding.isFeedSwipeHintAllowed)
        #expect(preferences.feedSwipeHintShown)
        onboarding.showFeedSwipeHint()
        await onboarding.decideFeedSwipeHint { "hidden" }
        #expect(!onboarding.showsFeedSwipeHint)
    }

    @Test("indication du feed, témoin : affichée")
    func shownSwipeHint() async {
        let onboarding = OnboardingModel(preferences: preferences)
        #expect(!onboarding.isFeedSwipeHintAllowed)
        await onboarding.decideFeedSwipeHint { "shown" }
        #expect(onboarding.showsFeedSwipeHint)
        #expect(onboarding.isFeedSwipeHintAllowed)
    }
}
