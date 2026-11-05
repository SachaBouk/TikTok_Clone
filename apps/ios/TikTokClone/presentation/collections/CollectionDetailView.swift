import Observation
import SwiftUI

// Page d'une collection (ADR-072), comme TikTok : nom en grand, « N publications » (cadenas si privée), « Gérer » pour son
// titulaire, flèche de partage (collection publique), puis ses vidéos en grille (lecteur vertical au toucher).
@MainActor
@Observable
final class CollectionDetailModel {
    enum State: Equatable {
        case loading, loaded
        case failed(String)
    }

    private(set) var collection: VideoCollection?
    private(set) var state: State
    let id: String
    let videos: PagedList<FeedVideo>
    private let useCase: CollectionsUseCase
    private let session: SessionStore

    init(route: CollectionRoute, useCase: CollectionsUseCase, videos: PagedList<FeedVideo>, session: SessionStore) {
        id = route.id
        collection = route.preview
        state = route.preview == nil ? .loading : .loaded
        self.useCase = useCase
        self.videos = videos
        self.session = session
    }

    var isOwn: Bool { collection.map { $0.owner.id == session.profile?.id } ?? false }

    func load() async {
        do {
            collection = try await useCase.get(id: id)
            state = .loaded
            await videos.loadFirst()
        } catch {
            let error = AppError.from(error)
            if error == .sessionExpired { session.sessionExpired() }
            state = .failed(error == .notFound ? "Cette collection n’est plus disponible." : error.message)
        }
    }

    // Collection changée ailleurs (son modèle partagé) : nom, visibilité, nombre de vidéos.
    func update(_ updated: VideoCollection) {
        collection = updated
    }
}

struct CollectionDetailView: View {
    @State private var model: CollectionDetailModel
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationPath) private var navigationPath
    @State private var isManaging = false
    @State private var manageAction: ManageAction?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingDelete = false
    @State private var isAdding = false
    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var isSharing = false
    @State private var errorMessage: String?

    enum ManageAction {
        case add, select, rename, togglePublic, delete
    }

    init(model: CollectionDetailModel, container: AppContainer) {
        _model = State(initialValue: model)
        self.container = container
    }

    var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let collection = model.collection, collection.isPublic, !isSelecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Partager la collection", systemImage: "arrowshape.turn.up.right") { isSharing = true }
                            .accessibilityIdentifier("collection.share")
                    }
                }
            }
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .task { await model.load() }
            .onChange(of: container.collections.version) {
                if let updated = container.collections.mine.first(where: { $0.id == model.id }) { model.update(updated) }
                Task { await model.videos.loadFirst() }
            }
            .sheet(isPresented: $isManaging, onDismiss: runManageAction) {
                manageSheet
                    .presentationDetents([.height(380)])
                    .presentationCornerRadius(20)
                    .presentationBackground(Color(.systemBackground))
            }
            .sheet(isPresented: $isSharing) {
                if let collection = model.collection {
                    ProfileShareSheet(profile: collection.owner, isBlocked: false, container: container, collection: collection) { _ in }
                        .presentationDetents([.height(330), .large])
                        .presentationCornerRadius(16)
                        .presentationBackground(.white)
                        .environment(\.colorScheme, .light)
                }
            }
            .navigationDestination(isPresented: $isAdding) {
                FavoritesPickerView(
                    container: container, title: "Ajouter des publications", actionTitle: "Ajouter",
                    excluded: Set(model.videos.items.map(\.id))
                ) { ids in
                    await add(ids)
                }
            }
            .alert("Changer de nom", isPresented: $isRenaming) {
                TextField("Nom de la collection", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("Enregistrer") { Task { await rename() } }
            }
            .confirmationDialog("Supprimer la collection ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Les vidéos restent dans tes favoris.")
            }
            .alert("Collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Collection indisponible", systemImage: "bookmark.slash", description: Text(message))
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let collection = model.collection { header(collection) }
                    if isSelecting {
                        selectionGrid
                    } else {
                        VideoGrid(
                            list: model.videos, previews: [:],
                            route: { page, index in VideoPlayerRoute(list: .collection(id: model.id), page: page, startIndex: index) },
                            emptyTitle: model.isOwn ? "Ajoute des favoris à cette collection" : "Aucune vidéo"
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
        }
    }

    private func header(_ collection: VideoCollection) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name).font(.system(size: 30, weight: .bold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(collection.countLabel)
                    if !collection.isPublic { Image(systemName: "lock").accessibilityLabel("Privée") }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                if !model.isOwn {
                    Text("par @\(collection.owner.username)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isOwn, !isSelecting {
                Button("Gérer") { isManaging = true }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("collection.manage")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // « Gérer la collection » : ajouter, sélectionner (pour retirer), changer de nom, rendre publique ou privée, supprimer.
    private var manageSheet: some View {
        VStack(spacing: 0) {
            Text("Gérer la collection").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 18)
            manageRow("Ajouter des publications", systemImage: "plus", action: .add)
            Divider().padding(.horizontal, 16)
            manageRow("Sélectionner des publications", systemImage: "checkmark.square", action: .select)
            Divider().padding(.horizontal, 16)
            manageRow("Changer de nom", systemImage: "square.and.pencil", action: .rename)
            Divider().padding(.horizontal, 16)
            manageRow(
                model.collection?.isPublic == true ? "Rendre privée" : "Rendre publique",
                systemImage: model.collection?.isPublic == true ? "lock" : "lock.open", action: .togglePublic)
            Divider().padding(.horizontal, 16)
            manageRow("Supprimer la collection", systemImage: "trash", action: .delete, role: .destructive)
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("collection.manageSheet")
    }

    private func manageRow(_ title: String, systemImage: String, action: ManageAction, role: ButtonRole? = nil) -> some View {
        Button {
            manageAction = action
            isManaging = false
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage).font(.title3).frame(width: 28)
                Text(title).font(.title3.weight(.medium))
                Spacer()
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collection.manage.\(String(describing: action))")
    }

    // L'action choisie s'enchaîne une fois la feuille fermée (une alerte présentée pendant la fermeture serait ignorée).
    private func runManageAction() {
        guard let action = manageAction, let collection = model.collection else { return }
        manageAction = nil
        switch action {
        case .add: isAdding = true
        case .select:
            selected = []
            isSelecting = true
        case .rename:
            newName = collection.name
            isRenaming = true
        case .togglePublic: Task { await setPublic(!collection.isPublic) }
        case .delete: isConfirmingDelete = true
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var selectionGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(model.videos.items) { video in
                let isSelected = selected.contains(video.id)
                Button {
                    if isSelected { selected.remove(video.id) } else { selected.insert(video.id) }
                } label: {
                    VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: nil)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(.white, isSelected ? Color.brandPink : Color.clear)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityVideoCell(video, showsViews: false)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("collection.selectVideo")
                .task { await model.videos.loadMore(ifNeededAfter: video) }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button("Annuler") { isSelecting = false }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(.secondarySystemFill), in: Capsule())
            Button(selected.isEmpty ? "Retirer" : "Retirer (\(selected.count))") { Task { await removeSelected() } }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.brandPink.opacity(selected.isEmpty ? 0.45 : 1), in: Capsule())
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("collection.removeSelected")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func add(_ ids: [String]) async {
        guard let collection = model.collection, !ids.isEmpty else {
            isAdding = false
            return
        }
        apply(await container.collections.add(videoIDs: ids, to: collection))
        isAdding = false
    }

    private func removeSelected() async {
        guard let collection = model.collection else { return }
        apply(await container.collections.remove(videoIDs: Array(selected), from: collection))
        isSelecting = false
    }

    private func rename() async {
        guard let collection = model.collection else { return }
        apply(await container.collections.rename(collection, to: newName))
    }

    private func setPublic(_ isPublic: Bool) async {
        guard let collection = model.collection else { return }
        apply(await container.collections.setPublic(isPublic, collection))
    }

    private func delete() async {
        guard let collection = model.collection else { return }
        if let error = await container.collections.delete(collection) {
            if error != .sessionExpired { errorMessage = error.message }
        } else {
            dismiss()
        }
    }

    private func apply(_ result: Result<VideoCollection, AppError>) {
        switch result {
        case .success(let updated): model.update(updated)
        case .failure(let error): if error != .sessionExpired { errorMessage = error.message }
        }
    }
}
