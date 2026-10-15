import SwiftUI

// Menu ☰ de son profil, comme TikTok (ADR-057) : panneau blanc qui glisse depuis la droite, par-dessus les onglets
// (fond assombri). Toucher le fond, glisser vers la droite ou choisir une ligne le ferme ; la ligne pousse sa page
// dans la pile du profil. Hors périmètre : vidéos hors ligne, TikTok Minis, TikTok Studio, Promouvoir.
struct ProfileMenuOverlay: View {
    @Binding var isOpen: Bool
    let onSelect: (AccountRoute) -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if isOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isOpen = false }
                    .accessibilityLabel("Fermer le menu")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                panel
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = max(0, $0.translation.width) }
                            .onEnded { value in
                                if value.translation.width > 80 || value.predictedEndTranslation.width > 200 { isOpen = false }
                                dragOffset = 0
                            }
                    )
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isOpen)
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header("Ressources")
                row("Solde", systemImage: "wallet.bifold", route: .wallet(.menu), id: "wallet")
                Divider().padding(.vertical, 12)
                header("Outils personnels")
                row("Centre des activités", systemImage: "clock", route: .activityCenter, id: "activityCenter")
                row("Ton code QR", systemImage: "qrcode", route: .qrCode, id: "qrCode")
                Divider().padding(.vertical, 12)
                row("Paramètres et confidentialité", systemImage: "gearshape", route: .settings, id: "settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }
        .background(Color(.systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("profileMenu")
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ title: String, systemImage: String, route: AccountRoute, id: String) -> some View {
        Button {
            isOpen = false
            onSelect(route)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                Text(title).font(.title3.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profileMenu.\(id)")
    }
}
