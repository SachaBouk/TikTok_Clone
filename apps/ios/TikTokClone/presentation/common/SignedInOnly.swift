import SwiftUI

// Contenu réservé aux comptes connectés (ADR-010) ; en invité, une invitation à se connecter.
struct SignedInOnly<Content: View>: View {
    let title: String
    let systemImage: String
    let reason: String
    // Accès à la confidentialité (mesure d'audience) sans compte : onglet Profil.
    var showsPrivacy = false
    @ViewBuilder let content: () -> Content
    @Environment(SessionStore.self) private var session
    @State private var isShowingPrivacy = false

    var body: some View {
        if session.isSignedIn {
            content()
        } else {
            NavigationStack {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(reason)
                } actions: {
                    Button("Se connecter") { session.requestSignIn() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("signInPrompt.signIn")
                    if showsPrivacy {
                        Button("Confidentialité") { isShowingPrivacy = true }
                            .accessibilityIdentifier("signInPrompt.privacy")
                    }
                }
                .navigationTitle(title)
                .sheet(isPresented: $isShowingPrivacy) { PrivacySettingsView() }
            }
        }
    }
}
