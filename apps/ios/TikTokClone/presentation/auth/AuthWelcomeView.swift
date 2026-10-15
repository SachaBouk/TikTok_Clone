import SwiftUI

// Écrans « Connexion » et « Inscription » (ADR-055), comme TikTok : grand titre, un bouton par moyen de connexion, et
// en bas le lien vers l'autre écran. Un seul moyen pour l'instant : email ou pseudo pour se connecter, email pour
// s'inscrire ; chacun ouvre son formulaire dans la même pile.
struct AuthWelcomeView: View {
    enum Mode {
        case login, signup
    }

    @State var mode: Mode
    // Invitation de l'expérience « invitation invité » (ADR-013).
    let invitation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode == .login ? "Connexion à\nTikTok Clone" : "Inscription à\nTikTok Clone")
                .font(.system(size: 34, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            if let invitation {
                Label(invitation, systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .accessibilityIdentifier("login.invitation")
            }
            VStack(spacing: 12) {
                switch mode {
                case .login:
                    AuthMethodButton(title: "Email ou nom d’utilisateur", systemImage: "person", route: .login)
                        .accessibilityIdentifier("auth.method.login")
                case .signup:
                    AuthMethodButton(title: "Email", systemImage: "person", route: .register)
                        .accessibilityIdentifier("auth.method.signup")
                }
            }
            .padding(.top, 40)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .safeAreaInset(edge: .bottom) { switcher }
        .animation(.snappy, value: mode)
    }

    // « Pas encore de compte ? S'inscrire » / « Déjà un compte ? Se connecter », sur un bandeau gris en bas.
    private var switcher: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Text(mode == .login ? "Pas encore de compte ?" : "Déjà un compte ?")
                Button(mode == .login ? "S’inscrire" : "Se connecter") {
                    mode = mode == .login ? .signup : .login
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.brandPink)
                .accessibilityIdentifier(mode == .login ? "auth.switch.signup" : "auth.switch.login")
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.secondarySystemBackground))
        }
    }
}

// Bouton à contour, icône à gauche et titre centré, comme les boutons de connexion de TikTok.
private struct AuthMethodButton: View {
    let title: String
    let systemImage: String
    let route: AuthFlowView.Route

    var body: some View {
        NavigationLink(value: route) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
