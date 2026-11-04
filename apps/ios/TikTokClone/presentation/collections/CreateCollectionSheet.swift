import SwiftUI

// « Créer une nouvelle collection » (ADR-072), comme TikTok : nom, « Rendre public », puis « Suivant » qui propose de
// choisir des favoris (« Passer » la crée vide). Depuis la feuille « Enregistrer dans la collection » (`video`), la
// vidéo y est ajoutée directement : le bouton devient « Créer ». Hors périmètre : « Partager avec un(e) ami(e) ».
struct CreateCollectionSheet: View {
    let container: AppContainer
    var video: FeedVideo? = nil
    let onCreated: (VideoCollection) -> Void
    @State private var name = ""
    @State private var isPublic = false
    @State private var isPicking = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var cleanedName: String? { CollectionRules.cleanedName(name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nom").font(.headline)
                        TextField("Saisis le nom de la collection", text: $name)
                            .focused($isFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("createCollection.name")
                        if name.count > CollectionRules.maxNameLength {
                            Text("\(CollectionRules.maxNameLength) caractères au plus.").font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    Toggle(isOn: $isPublic) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rendre public").font(.headline)
                            Text("La collection sera affichée sur ton profil.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.brandCyan)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("createCollection.public")
                    Button {
                        if let video {
                            Task { await create(videoIDs: [video.id]) }
                        } else {
                            isPicking = true
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text(video == nil ? "Suivant" : "Créer")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.brandPink.opacity(cleanedName == nil ? 0.45 : 1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(cleanedName == nil || isSaving)
                    .accessibilityIdentifier("createCollection.next")
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Créer une nouvelle collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isPicking) {
                FavoritesPickerView(container: container, title: name, actionTitle: "Créer", allowsEmpty: true) { ids in
                    await create(videoIDs: ids)
                }
            }
            .alert("Collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .foregroundStyle(Color.primary)
        .onAppear { isFocused = true }
    }

    private func create(videoIDs: [String]) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        switch await container.collections.create(name: name, isPublic: isPublic, videoIDs: videoIDs) {
        case .success(let collection):
            if let video { container.videoInteractions.savedToCollection(video) }
            container.analytics.track(.collectionCreated(isPublic: isPublic, videos: videoIDs.count))
            dismiss()
            onCreated(collection)
        case .failure(let error):
            if error != .sessionExpired { errorMessage = error.message }
        }
    }
}

// Ses favoris à choisir (ADR-072), en grille à cocher : création d'une collection (« Créer », « Passer ») ou « Ajouter
// des publications » à une collection (`excluded` : les vidéos qu'elle contient déjà, grisées).
struct FavoritesPickerView: View {
    let container: AppContainer
    let title: String
    let actionTitle: String
    var allowsEmpty = false
    var excluded: Set<String> = []
    let action: ([String]) async -> Void
    @State private var list: PagedList<FeedVideo>?
    @State private var selected: [String] = []
    @State private var isSaving = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            if let list {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(list.items) { video in
                        cell(video)
                            .task { await list.loadMore(ifNeededAfter: video) }
                    }
                }
                if list.items.isEmpty, list.state == .loaded {
                    ContentUnavailableView(
                        "Aucun favori", systemImage: "bookmark", description: Text("Ajoute des vidéos à tes favoris avec le signet.")
                    )
                    .padding(.top, 40)
                }
            }
        }
        .navigationTitle(title.isEmpty ? "Favoris" : title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isSaving = true
                Task {
                    await action(selected)
                    isSaving = false
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else if selected.isEmpty {
                        Text(allowsEmpty ? "Passer" : actionTitle)
                    } else {
                        Text("\(actionTitle) (\(selected.count))")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.brandPink.opacity(selected.isEmpty && !allowsEmpty ? 0.45 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled((selected.isEmpty && !allowsEmpty) || isSaving)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("favoritesPicker.action")
        }
        .task {
            if list == nil { list = container.makeVideoPageList(.myFavorites) }
            await list?.loadFirstIfNeeded()
        }
    }

    private func cell(_ video: FeedVideo) -> some View {
        let isExcluded = excluded.contains(video.id)
        let index = selected.firstIndex(of: video.id)
        return Button {
            if let index {
                selected.remove(at: index)
            } else if selected.count < CollectionRules.maxBatch {
                selected.append(video.id)
            }
        } label: {
            VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: nil)
                .overlay(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(index == nil ? Color.black.opacity(0.25) : Color.brandPink)
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                        if let index { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white) }
                    }
                    .frame(width: 24, height: 24)
                    .padding(6)
                }
                .opacity(isExcluded ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isExcluded)
        .accessibilityLabel(isExcluded ? "Déjà dans la collection" : index == nil ? "Choisir cette vidéo" : "Vidéo choisie")
        .accessibilityIdentifier("favoritesPicker.video")
    }
}
