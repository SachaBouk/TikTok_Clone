import SwiftUI
import UIKit

// Icônes de l'app au choix (ADR-073), réservées aux abonnés « Plus » : l'icône d'origine et trois variantes du logo
// (Or, Néon, Rétro). Le choix est fait par iOS (`setAlternateIconName`, qui affiche sa propre alerte). Sans abonnement,
// les variantes sont verrouillées et ouvrent le paywall ; à l'échéance, l'icône d'origine revient au lancement suivant
// (`AppIconReset`).
struct AppIconSettingsView: View {
    let container: AppContainer
    @Environment(AnalyticsModel.self) private var analytics
    @State private var current: AppIcon? = AppIcon(rawValue: UIApplication.shared.alternateIconName ?? "")
    @State private var isPresentingPlus = false
    @State private var errorMessage: String?

    private var isPlus: Bool { container.plus.isActive }

    var body: some View {
        List {
            Section {
                row(nil, title: "D’origine", preview: Image(systemName: "music.note"))
                ForEach(AppIcon.allCases) { icon in
                    row(icon, title: icon.title, preview: Image("\(icon.rawValue)Preview"))
                }
            } footer: {
                Text(
                    isPlus
                        ? "Le changement s’applique aussitôt sur l’écran d’accueil." : "Les icônes Or, Néon et Rétro sont réservées aux abonnés Plus."
                )
            }
        }
        .navigationTitle("Icône de l’app")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingPlus) { PlusSheet(source: .appIcon, container: container) }
        .alert("Icône de l’app", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("appIcons")
    }

    private func row(_ icon: AppIcon?, title: String, preview: Image) -> some View {
        let isLocked = icon != nil && !isPlus
        return Button {
            if isLocked {
                isPresentingPlus = true
                return
            }
            choose(icon)
        } label: {
            HStack(spacing: 14) {
                Group {
                    if icon == nil {
                        AppLogo(size: 26).frame(width: 52, height: 52).background(.black)
                    } else {
                        preview.resizable().scaledToFill().frame(width: 52, height: 52)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else if current == icon {
                    Image(systemName: "checkmark").foregroundStyle(Color.brandPink).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(current == icon ? .isSelected : [])
        .accessibilityValue(isLocked ? "Réservée aux abonnés Plus" : "")
        .accessibilityIdentifier("appIcons.\(icon?.rawValue ?? "default")")
    }

    private func choose(_ icon: AppIcon?) {
        guard icon != current, UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(icon?.rawValue)
                current = icon
                analytics.track(.appIconChanged(icon))
            } catch {
                errorMessage = "Impossible de changer l’icône pour l’instant."
            }
        }
    }
}

// Abonnement échu (ADR-073) : l'icône d'origine revient, une fois l'état de l'abonnement connu.
@MainActor
enum AppIconReset {
    static func applyIfNeeded(isPlus: Bool) {
        guard !isPlus, UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != nil else { return }
        Task { try? await UIApplication.shared.setAlternateIconName(nil) }
    }
}
