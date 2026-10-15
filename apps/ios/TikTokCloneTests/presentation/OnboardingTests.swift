import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@MainActor
@Suite("Onboarding et connexion par email ou pseudo (ADR-055)")
struct OnboardingTests {
    @Test("premier lancement sans compte : onboarding, une seule fois ; déjà connecté : jamais")
    func firstLaunch() {
        let preferences = InMemoryPreferencesStore()
        let onboarding = OnboardingModel(preferences: preferences)
        onboarding.sessionRestored(signedIn: false)
        #expect(onboarding.isPresented)
        onboarding.finish()
        #expect(!onboarding.isPresented)
        #expect(preferences.onboardingCompleted)

        let again = OnboardingModel(preferences: preferences)
        again.sessionRestored(signedIn: false)
        #expect(!again.isPresented)

        let signedInPreferences = InMemoryPreferencesStore()
        let signedIn = OnboardingModel(preferences: signedInPreferences)
        signedIn.sessionRestored(signedIn: true)
        #expect(!signedIn.isPresented)
        #expect(signedInPreferences.onboardingCompleted)
    }

    @Test("connexion : l'identifiant (email ou pseudo) part dans le champ `identifier`")
    func loginBody() async throws {
        let bodies = BodyLog()
        let client = makeClient(
            transport: MockTransport(
                handler: { _, _ in json(.ok, #"{"accessToken":"A","accessTokenExpiresIn":900,"refreshToken":"R"}"#) }, bodies: bodies))
        try await RemoteAuthRepository(client: client, store: InMemoryTokenStore()).login(identifier: "lea.martin", password: "motdepasse")
        let sent = try #require(bodies.all.first)
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: String])
        #expect(fields["identifier"] == "lea.martin")
        #expect(fields["email"] == nil)
    }

    @Test("écran de connexion : source de la mesure d'audience")
    func authSource() {
        #expect(AnalyticsEvent.authSheetShown(source: .onboarding).properties["source"] == .string("onboarding"))
        #expect(AnalyticsEvent.authSheetShown(source: .prompt).properties["source"] == .string("prompt"))
    }
}
