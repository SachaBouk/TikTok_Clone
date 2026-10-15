import SwiftUI

// « Centre des activités », ouvert par le menu ☰ de son profil, comme TikTok (ADR-057) : les historiques.
// Hors périmètre : activité publicitaire, mentions, historique du compte, réutilisation du contenu.
struct ActivityCenterView: View {
    var body: some View {
        List {
            NavigationLink(value: AccountRoute.viewHistory) {
                Label("Historique de visionnage", systemImage: "play.circle.fill")
            }
            .accessibilityIdentifier("activityCenter.viewHistory")
            NavigationLink(value: AccountRoute.commentHistory) {
                Label("Historique des commentaires", systemImage: "ellipsis.bubble.fill")
            }
            .accessibilityIdentifier("activityCenter.commentHistory")
            NavigationLink(value: AccountRoute.searchHistory) {
                Label("Historique des recherches", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("activityCenter.searchHistory")
        }
        .labelStyle(SettingsLabelStyle())
        .navigationTitle("Centre des activités")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// « Historique des recherches » (ADR-057) : recherches gardées sur l'appareil (ADR-049), rangées par jour, avec
// l'heure ; toucher relance la recherche ; glisser ou « Sélectionner » pour supprimer.
struct SearchHistoryView: View {
    let history: SearchHistoryModel
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var isConfirmingClear = false

    private var isSelecting: Bool { editMode.isEditing }

    var body: some View {
        List(selection: $selection) {
            ForEach(DaySections.group(history.entries, date: \.searchedAt)) { section in
                Section {
                    ForEach(section.items, id: \.query) { entry in
                        NavigationLink(value: SearchRoute(query: entry.query)) {
                            SearchHistoryRow(entry: entry)
                        }
                        .swipeActions {
                            Button("Supprimer", systemImage: "trash", role: .destructive) { history.remove(entry.query) }
                        }
                    }
                } header: {
                    Text(section.title).font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView("Aucune recherche", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("Historique des recherches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Annuler" : "Sélectionner") {
                    withAnimation { editMode = isSelecting ? .inactive : .active }
                    selection = []
                }
                .disabled(history.entries.isEmpty && !isSelecting)
                .accessibilityIdentifier("searchHistory.select")
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Tout effacer", role: .destructive) { isConfirmingClear = true }
                    Spacer()
                    Button("Supprimer (\(selection.count))", role: .destructive) {
                        history.remove(selection)
                        selection = []
                        withAnimation { editMode = .inactive }
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("searchHistory.delete")
                }
            }
        }
        // La barre « Tout effacer | Supprimer » passerait sous la barre d'onglets.
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        .confirmationDialog("Effacer tout l’historique des recherches ?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Effacer l’historique", role: .destructive) {
                history.clear()
                selection = []
                withAnimation { editMode = .inactive }
            }
        }
    }
}

private struct SearchHistoryRow: View {
    let entry: SearchHistoryEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "magnifyingglass").font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.query).font(.body.weight(.medium)).lineLimit(2)
                if let searchedAt = entry.searchedAt {
                    Text(searchedAt, format: .dateTime.hour().minute()).font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
