import SwiftUI

// Éléments communs des écrans de l'inscription (ADR-055), dessinés comme ceux de TikTok : grand titre, champ souligné,
// bouton plein rose.

struct SignupHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Champ sans cadre, souligné d'un trait, avec un bouton d'effacement quand il n'est pas vide.
struct UnderlinedField<Field: View, Trailing: View>: View {
    var text: Binding<String>?
    @ViewBuilder let field: () -> Field
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                field()
                    .font(.body)
                if let text, !text.wrappedValue.isEmpty {
                    Button("Effacer", systemImage: "xmark.circle.fill") { text.wrappedValue = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                }
                trailing()
            }
            .frame(minHeight: 30)
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
    }
}

extension UnderlinedField where Trailing == EmptyView {
    init(text: Binding<String>?, @ViewBuilder field: @escaping () -> Field) {
        self.text = text
        self.field = field
        self.trailing = { EmptyView() }
    }
}

// Bouton plein rose, gris tant qu'il n'est pas utilisable ; points d'attente pendant l'envoi.
struct SignupPrimaryButton: View {
    let title: String
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    DotsLoader(size: 10, colors: (.white, .white.opacity(0.6)))
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(isEnabled ? Color.brandPink : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

// Bouton gris clair (« Passer »).
struct SignupSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.primary)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Message d'erreur sous un champ.
struct SignupErrorText: View {
    let message: String
    var identifier: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

extension View {
    // Mise en page commune : marges, contenu en haut.
    func signupPage() -> some View {
        padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Inscription")
            .navigationBarTitleDisplayMode(.inline)
    }
}
