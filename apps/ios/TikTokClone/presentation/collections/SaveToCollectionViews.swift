import SwiftUI

// Appui long sur le signet d'une vidéo (ADR-072), comme TikTok : petite bulle blanche avec ses trois collections les plus
// récemment utilisées (image et nom) puis « Plus ». Toucher une collection y enregistre la vidéo (mise en favori si
// besoin) ; « Plus » ouvre « Enregistrer dans la collection ».
struct CollectionQuickMenu: View {
    let collections: [VideoCollection]
    let choose: (VideoCollection) -> Void
    let more: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(collections) { collection in
                row(title: collection.name, identifier: "quickMenu.collection") {
                    CollectionThumbnail(url: collection.coverURL, size: 36)
                } action: {
                    choose(collection)
                }
                Divider()
            }
            row(title: "Plus", identifier: "quickMenu.more") {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            } action: {
                more()
            }
        }
        .frame(width: 250)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func row(title: String, identifier: String, @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon()
                Text(title).font(.title3.weight(.medium)).foregroundStyle(.black).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

// Petite image carrée d'une collection (ou gris clair sans vidéo).
struct CollectionThumbnail: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Color(.systemGray5)
            .frame(width: size, height: size)
            .overlay {
                if let url { CachedThumbnail(url: url) }
            }
            .clipShape(RoundedRectangle(cornerRadius: size > 50 ? 10 : 6))
    }
}

// « Enregistrer dans la collection » (ADR-072) : ses collections (image, nom, cadenas si privée, nombre de vidéos) avec
// « + » pour y ajouter la vidéo (✓ une fois dedans ; le toucher l'en retire), et « Créer une nouvelle collection » en bas.
struct SaveToCollectionSheet: View {
    let video: FeedVideo
    let container: AppContainer
    @State private var collections: [VideoCollection] = []
    @State private var isLoading = true
    @State private var pending: Set<String> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Enregistrer dans la collection")
                .font(.headline)
                .padding(.top, 22)
                .padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        ProgressView().padding(.vertical, 40)
                    } else if collections.isEmpty {
                        Text("Tu n’as pas encore de collection.").foregroundStyle(.secondary).padding(.vertical, 32)
                    }
                    ForEach(collections) { collection in
                        row(collection)
                    }
                }
            }
            Divider()
            Button {
                isCreating = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.split.2x2")
                        .font(.title2)
                        .foregroundStyle(Color(.systemGray3))
                        .frame(width: 60, height: 60)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Créer une nouvelle collection").font(.headline)
                        Text("Organise les publications pour pouvoir les consulter à nouveau rapidement")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "plus").font(.title2)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("saveToCollection.create")
        }
        // Présentée depuis la colonne du feed, qui écrit en blanc : texte remis aux couleurs du système.
        .foregroundStyle(Color.primary)
        .task { await load() }
        .sheet(isPresented: $isCreating) {
            CreateCollectionSheet(container: container, video: video) { _ in dismiss() }
                .presentationDetents([.large])
        }
        .alert("Collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("saveToCollection.sheet")
    }

    private func row(_ collection: VideoCollection) -> some View {
        let contains = collection.containsVideo == true
        return HStack(spacing: 14) {
            CollectionThumbnail(url: collection.coverURL, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(collection.name).font(.headline).lineLimit(1)
                    if !collection.isPublic { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(collection.countLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await toggle(collection) }
            } label: {
                Group {
                    if pending.contains(collection.id) {
                        ProgressView()
                    } else {
                        Image(systemName: contains ? "checkmark" : "plus")
                            .font(.title2.weight(contains ? .semibold : .regular))
                            .foregroundStyle(contains ? Color.brandPink : Color.primary)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(contains ? "Retirer de \(collection.name)" : "Enregistrer dans \(collection.name)")
            .accessibilityIdentifier("saveToCollection.toggle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func load() async {
        switch await container.collections.collections(containing: video.id) {
        case .success(let loaded): collections = loaded
        case .failure(let error): if error != .sessionExpired { errorMessage = error.message }
        }
        isLoading = false
    }

    private func toggle(_ collection: VideoCollection) async {
        guard pending.insert(collection.id).inserted else { return }
        defer { pending.remove(collection.id) }
        let contains = collection.containsVideo == true
        let result =
            contains
            ? await container.collections.remove(videoIDs: [video.id], from: collection)
            : await container.collections.add(videoIDs: [video.id], to: collection)
        switch result {
        case .success(var updated):
            updated.containsVideo = !contains
            if let index = collections.firstIndex(where: { $0.id == collection.id }) { collections[index] = updated }
            if !contains {
                container.videoInteractions.savedToCollection(video)
                container.analytics.track(.savedToCollection(videoID: video.id, source: "sheet"))
            }
        case .failure(let error):
            if error != .sessionExpired { errorMessage = error.message }
        }
    }
}
