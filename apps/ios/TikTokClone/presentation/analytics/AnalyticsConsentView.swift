import SwiftUI

// Demande de consentement à la mesure d'audience (ADR-013, choix du développeur : opt-in, RGPD), au premier
// lancement : rien n'est envoyé avant la réponse. Refuser est aussi simple qu'accepter.
struct AnalyticsConsentView: View {
    @Environment(AnalyticsModel.self) private var analytics

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Aider à améliorer l’app ?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(AnalyticsConsentView.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { analytics.setConsent(true) } label: {
                    Text("Autoriser").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("consent.accept")
                Button { analytics.setConsent(false) } label: {
                    Text("Refuser").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("consent.decline")
            }
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    static let explanation = "Avec ton accord, l’app mesure son utilisation (vidéos regardées, réactions, inscription) et essaie des variantes de certains écrans, avec PostHog, hébergé dans l’Union européenne. Seul l’identifiant de ton compte est transmis : ni nom, ni pseudo, ni email, ni contenu de tes messages. Tu peux changer d’avis à tout moment dans les réglages."
}

// Réglage de la mesure d'audience (paramètres du compte, ou profil en invité).
struct AnalyticsConsentToggle: View {
    @Environment(AnalyticsModel.self) private var analytics

    var body: some View {
        Toggle("Mesure d’audience", isOn: Binding(
            get: { analytics.isEnabled },
            set: { analytics.setConsent($0) }
        ))
        .accessibilityIdentifier("settings.analytics")
    }
}

// Confidentialité, accessible sans compte (onglet Profil en invité).
struct PrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AnalyticsConsentToggle()
                } footer: {
                    Text(AnalyticsConsentView.explanation)
                }
            }
            .navigationTitle("Confidentialité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
