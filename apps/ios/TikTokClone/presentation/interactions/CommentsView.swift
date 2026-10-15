import SwiftUI

// Feuille de commentaires native (demi-hauteur, extensible). Glisser vers la gauche sur son commentaire
// pour le supprimer, sur celui d'un autre pour le signaler (ADR-038). Sur sa propre vidéo, le commentaire d'un autre
// peut aussi être supprimé, après confirmation et sans prévenir son auteur (ADR-042).
struct CommentsView: View {
    @State private var viewModel: CommentsViewModel
    let container: AppContainer
    @State private var isPresentingSignIn = false
    @State private var reportTarget: ReportTarget?
    // Auteur du commentaire signalé : l'écran de remerciement propose de le bloquer.
    @State private var reportedAuthor: UserSummary?
    // Commentaire d'un autre à supprimer de sa vidéo, en attente de confirmation.
    @State private var removing: VideoComment?
    @FocusState private var isComposing: Bool
    @Environment(\.dismiss) private var dismiss

    init(viewModel: CommentsViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { composer }
                .appDestinations(container)
        }
        .task { await viewModel.start() }
        // Blocage de l'auteur de la vidéo : la feuille se ferme (la vidéo quitte les écrans) ; d'un autre compte :
        // ses commentaires disparaissent.
        .onChange(of: container.videoInteractions.blockedUserIDs) { _, ids in
            if ids.contains(viewModel.video.author.id) { dismiss() } else { viewModel.removeComments(byAuthors: ids) }
        }
        .sheet(isPresented: $isPresentingSignIn) {
            AuthFlowView(container: container)
        }
        .reportSheet($reportTarget, container: container, author: reportedAuthor)
        .alert(
            "Commentaires",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var title: String {
        viewModel.count <= 1 ? "\(viewModel.count) commentaire" : "\(viewModel.count.formatted()) commentaires"
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.loadError {
            ContentUnavailableView {
                Label("Commentaires indisponibles", systemImage: "exclamationmark.bubble")
            } description: {
                Text(error)
            } actions: {
                Button("Réessayer") { Task { await viewModel.start() } }
            }
        } else if viewModel.comments.isEmpty {
            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Aucun commentaire", systemImage: "bubble.left.and.bubble.right", description: Text("Sois le premier à commenter."))
            }
        } else {
            List {
                ForEach(viewModel.comments) { comment in
                    // Toucher un commentaire ouvre le profil de son auteur, dans la feuille.
                    NavigationLink(value: ProfileRoute(username: comment.author.username)) {
                        CommentRow(comment: comment)
                    }
                    .swipeActions(edge: .trailing) {
                        if viewModel.isOwn(comment) {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.delete(comment) }
                            }
                        } else {
                            // Sans `role: .destructive` : le bouton retirerait la ligne avant la confirmation.
                            if viewModel.canDelete(comment) {
                                Button("Supprimer", systemImage: "trash") { removing = comment }
                                    .tint(.red)
                            }
                            Button("Signaler", systemImage: "flag") {
                                if viewModel.isSignedIn {
                                    reportedAuthor = comment.author
                                    reportTarget = .comment(id: comment.id)
                                } else {
                                    isPresentingSignIn = true
                                }
                            }
                            .tint(.orange)
                        }
                    }
                    // Attachée à la ligne : la confirmation s'affiche près du commentaire, pas dans un coin de l'écran.
                    .confirmationDialog(
                        "Supprimer ce commentaire ?",
                        isPresented: Binding(get: { removing?.id == comment.id }, set: { if !$0 { removing = nil } }),
                        titleVisibility: .visible
                    ) {
                        Button("Supprimer", role: .destructive) { Task { await viewModel.delete(comment) } }
                    } message: {
                        Text("Il disparaîtra pour tout le monde. @\(comment.author.username) ne sera pas prévenu(e).")
                    }
                }
                if viewModel.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task { await viewModel.loadMore() }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var composer: some View {
        Group {
            if viewModel.isSignedIn {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ajouter un commentaire…", text: $viewModel.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isComposing)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                        .accessibilityIdentifier("comments.field")
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        if viewModel.isSending {
                            ProgressView().frame(width: 34, height: 34)
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                        }
                    }
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel("Publier le commentaire")
                    .accessibilityIdentifier("comments.send")
                }
            } else {
                Button("Connecte-toi pour commenter") { isPresentingSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct CommentRow: View {
    let comment: VideoComment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: comment.author.avatarURL, name: comment.author.displayName, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author.username).font(.subheadline.bold())
                    Text.relative(comment.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(comment.content)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
