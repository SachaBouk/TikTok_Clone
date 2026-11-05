import SwiftUI

// Paramètres › Notifications (ADR-078) : sortes de bandeaux affichés quand l'app est ouverte, réglées sur l'appareil.
struct NotificationSettingsView: View {
    let banners: InAppBannerModel

    var body: some View {
        List {
            Section {
                ForEach(InAppBannerCategory.allCases) { category in
                    Toggle(isOn: Binding(get: { banners.isEnabled(category) }, set: { banners.setEnabled($0, for: category) })) {
                        Label(category.title, systemImage: category.systemImage)
                    }
                    .tint(.brandPink)
                    .accessibilityIdentifier("notifications.\(category.rawValue)")
                }
            } header: {
                Text("Bandeaux dans l’app")
            } footer: {
                Text(
                    "Un bandeau s’affiche en haut de l’écran quand l’app est ouverte. Rien n’est affiché quand l’app est fermée. Les décisions de modération sont toujours annoncées."
                )
            }
        }
        .labelStyle(SettingsLabelStyle())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
