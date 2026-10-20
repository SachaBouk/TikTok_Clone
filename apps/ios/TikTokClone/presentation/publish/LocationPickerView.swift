import SwiftUI

// « Ajouter un lieu » (ADR-065), comme TikTok : ×, champ « Rechercher des lieux » (Apple Plans), puis les lieux à proximité
// (« Afficher les lieux à proximité » demande la localisation) ou les résultats ; nom en gras, adresse en gris.
struct LocationPickerView: View {
    let model: PlacePickerModel
    let onPick: (VideoLocation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Ajouter un lieu").font(.headline)
                HStack {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("location.close")
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher des lieux", text: $text)
                    .focused($searching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, value in model.search(value) }
                    .accessibilityIdentifier("location.search")
                if !text.isEmpty {
                    Button("Effacer", systemImage: "xmark.circle.fill") { text = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            List {
                if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    nearbySection
                } else if model.isSearching && model.results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }.listRowSeparator(.hidden)
                } else if let message = model.errorMessage {
                    Text(message).foregroundStyle(.secondary).listRowSeparator(.hidden)
                } else if model.results.isEmpty {
                    Text("Aucun lieu trouvé").foregroundStyle(.secondary).listRowSeparator(.hidden)
                } else {
                    ForEach(model.results) { row($0) }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .task { await model.loadNearby() }
    }

    @ViewBuilder
    private var nearbySection: some View {
        switch model.access {
        case .authorized:
            if !model.nearby.isEmpty {
                Section {
                    ForEach(model.nearby) { row($0) }
                } header: {
                    Text("Lieux populaires près de toi").font(.subheadline).foregroundStyle(.secondary).textCase(nil)
                }
            }
        case .notDetermined:
            Button {
                Task { await model.allowNearby() }
            } label: {
                Label("Afficher les lieux à proximité", systemImage: "location")
                    .font(.headline)
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 6)
            .accessibilityIdentifier("location.allowNearby")
        case .denied:
            Text("Autorise la localisation dans Réglages pour voir les lieux à proximité.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
        }
    }

    private func row(_ place: VideoLocation) -> some View {
        Button {
            onPick(place)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline).foregroundStyle(.primary)
                if let address = place.address {
                    Text(address).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("location.place.\(place.name)")
    }
}
