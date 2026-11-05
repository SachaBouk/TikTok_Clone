import SwiftUI

// Conteneur de l'app pour les vues profondes qui ouvrent leurs propres feuilles (signet du feed, ADR-072).
extension EnvironmentValues {
    @Entry var appContainer: AppContainer? = nil
}

// Route d'une collection (ADR-072) : son identifiant, et la collection déjà connue (affichée pendant le chargement).
struct CollectionRoute: Hashable, Identifiable {
    let id: String
    var preview: VideoCollection? = nil
}

// Carte d'une collection, comme TikTok : image (dernière vidéo), signet, nom en blanc, cadenas si elle est privée.
struct CollectionCard: View {
    let collection: VideoCollection

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = collection.coverURL { CachedThumbnail(url: url) }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 20, weight: .semibold))
                    HStack {
                        Text(collection.name).font(.headline).lineLimit(1)
                        Spacer(minLength: 4)
                        if !collection.isPublic {
                            Image(systemName: "lock").font(.subheadline.weight(.semibold)).accessibilityLabel("Privée")
                        }
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("collection.card")
    }
}

// Grille des collections en deux colonnes ; sur son profil, « + Créer une nouvelle collection › » en tête.
struct CollectionsGrid: View {
    let collections: [VideoCollection]
    let isOwn: Bool
    var isLoading = false
    let open: (VideoCollection) -> Void
    var create: () -> Void = {}

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    var body: some View {
        VStack(spacing: 0) {
            if isOwn {
                Button(action: create) {
                    HStack(spacing: 14) {
                        Image(systemName: "plus").font(.title3.weight(.medium))
                        Text("Créer une nouvelle collection").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("collections.create")
            }
            if collections.isEmpty {
                if isLoading {
                    ProgressView().padding(.vertical, 40)
                } else if !isOwn {
                    ContentUnavailableView("Aucune collection publique", systemImage: "bookmark")
                        .padding(.vertical, 24)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(collections) { collection in
                        Button {
                            open(collection)
                        } label: {
                            CollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

// Sous-onglets de l'onglet favoris (ADR-072) : « Publications » et « Collections N », le choisi en noir.
struct FavoritesSegments: View {
    enum Segment: Hashable {
        case publications, collections
    }

    @Binding var selection: Segment
    let collectionsCount: Int?

    var body: some View {
        HStack(spacing: 28) {
            segment(.publications, "Publications")
            segment(.collections, collectionsCount.map { "Collections \($0)" } ?? "Collections")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func segment(_ segment: Segment, _ title: String) -> some View {
        Button {
            selection = segment
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(selection == segment ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == segment ? .isSelected : [])
        .accessibilityIdentifier("favorites.\(segment == .publications ? "publications" : "collections")")
    }
}
