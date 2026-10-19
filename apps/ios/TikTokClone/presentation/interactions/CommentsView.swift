import SwiftUI

// Feuille de commentaires façon TikTok (ADR-060) : « N commentaires » et ×, puis les commentaires (nom, badge
// « Créateur », texte avec mentions et hashtags cliquables, date, « Répondre », « aimé par l'auteur », cœur, « Je n'aime
// pas ») et leurs fils de réponses repliés ; en bas, la barre d'emojis et le champ (« @ », flèche rose d'envoi).
// Glisser vers la gauche sur son commentaire pour le supprimer, sur celui d'un autre pour le signaler (ADR-038). Sur sa
// propre vidéo, le commentaire d'un autre peut aussi être supprimé, après confirmation et sans prévenir son auteur (ADR-042).
struct CommentsView: View {
    @State private var viewModel: CommentsViewModel
    let container: AppContainer
    @State private var path = NavigationPath()
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
        NavigationStack(path: $path) {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title).font(.subheadline.weight(.semibold))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                            .accessibilityIdentifier("comments.close")
                    }
                }
                .safeAreaInset(edge: .bottom) { composer }
                .appDestinations(container)
        }
        .providesNavigationPath($path)
        .task { await viewModel.start() }
        // Suggestions de la mention en cours de saisie, 250 ms après la frappe.
        .task(id: viewModel.draft) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await viewModel.updateMentionSuggestions()
        }
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
            } else if !commentsEnabled {
                ContentUnavailableView(
                    "Commentaires désactivés", systemImage: "text.bubble", description: Text("Les commentaires sont désactivés pour cette vidéo."))
            } else {
                ContentUnavailableView(
                    "Aucun commentaire", systemImage: "bubble.left.and.bubble.right", description: Text("Sois le premier à commenter."))
            }
        } else {
            List {
                ForEach(viewModel.rows) { row in
                    rowView(row)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
                }
                if viewModel.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task { await viewModel.loadMore() }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func rowView(_ row: CommentsViewModel.Row) -> some View {
        switch row {
        case .comment(let comment):
            commentRow(comment)
        case .reply(let comment):
            commentRow(comment)
                .padding(.leading, CommentRow.replyIndent)
        case .thread(let parent, let remaining, let isExpanded, let isLoading):
            ThreadControlRow(remaining: remaining, isExpanded: isExpanded, isLoading: isLoading) {
                Task { await viewModel.showReplies(of: parent) }
            } hide: {
                viewModel.hideReplies(of: parent)
            }
            .padding(.leading, CommentRow.replyIndent)
        }
    }

    private func commentRow(_ comment: VideoComment) -> some View {
        CommentRow(
            comment: comment,
            isCreator: viewModel.isCreator(comment),
            isDisliked: viewModel.isDisliked(comment),
            creatorAvatarURL: viewModel.video.author.avatarURL,
            creatorName: viewModel.video.author.displayName,
            actions: .init(
                openProfile: { path.append(ProfileRoute(username: $0)) },
                openHashtag: { path.append(HashtagRoute(name: $0)) },
                reply: {
                    viewModel.reply(to: comment)
                    if viewModel.isSignedIn { isComposing = true }
                },
                like: { Task { await viewModel.toggleLike(comment) } },
                dislike: { viewModel.toggleDislike(comment) }
            )
        )
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
            Text(
                comment.isReply || comment.repliesCount == 0
                    ? "Il disparaîtra pour tout le monde. @\(comment.author.username) ne sera pas prévenu(e)."
                    : "Il disparaîtra pour tout le monde, avec ses réponses. @\(comment.author.username) ne sera pas prévenu(e).")
        }
    }

    // Commentaires autorisés, changements faits dans l'app compris (ADR-062).
    private var commentsEnabled: Bool {
        container.videoInteractions.display(viewModel.video).commentsEnabled
    }

    // Bas de la feuille : suggestions de mention, bandeau de réponse, barre d'emojis, champ.
    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            if !commentsEnabled {
                // Commentaires coupés par l'auteur (ADR-062) : ni commentaire, ni réponse.
                Text("Les commentaires sont désactivés pour cette vidéo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("comments.disabled")
            } else if viewModel.isSignedIn {
                if !viewModel.mentionSuggestions.isEmpty { mentionSuggestions }
                if let replyingTo = viewModel.replyingTo {
                    HStack {
                        Text("Réponse à @\(replyingTo.author.username)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Annuler la réponse", systemImage: "xmark") { viewModel.cancelReply() }
                            .labelStyle(.iconOnly)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("comments.cancelReply")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                }
                emojiBar
                field
            } else {
                Button("Connecte-toi pour commenter") { isPresentingSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandPink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(.systemBackground))
    }

    // Un toucher ajoute l'emoji au texte, comme TikTok.
    private var emojiBar: some View {
        HStack {
            ForEach(CommentRules.quickEmojis, id: \.self) { emoji in
                Button {
                    viewModel.addEmoji(emoji)
                    isComposing = true
                } label: {
                    Text(emoji).font(.system(size: 30)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter \(emoji)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(url: viewModel.ownProfile?.avatarURL, name: viewModel.ownProfile?.displayName ?? "", size: 36)
                HStack(spacing: 8) {
                    TextField(placeholder, text: $viewModel.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isComposing)
                        .accessibilityIdentifier("comments.field")
                    if !isComposing { mentionButton }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: Capsule())
            }
            // Pendant la saisie, comme TikTok : « @ » et la flèche rose sous le champ.
            if isComposing {
                HStack(spacing: 18) {
                    mentionButton
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Group {
                            if viewModel.isSending {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 32)
                        .background(Color.brandPink.opacity(viewModel.canSend ? 1 : 0.4), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel("Publier le commentaire")
                    .accessibilityIdentifier("comments.send")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var placeholder: String {
        viewModel.replyingTo.map { "Répondre à @\($0.author.username)" } ?? "Ajouter un commentaire…"
    }

    private var mentionButton: some View {
        Button {
            viewModel.startMention()
            isComposing = true
        } label: {
            Image(systemName: "at").font(.system(size: 20, weight: .medium)).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mentionner un compte")
        .accessibilityIdentifier("comments.mention")
    }

    // Comptes proposés pour la mention en cours de saisie : un toucher complète « @pseudo ».
    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.mentionSuggestions.prefix(4), id: \.id) { user in
                Button {
                    viewModel.chooseMention(user)
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(url: user.avatarURL, name: user.displayName, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.displayName).font(.subheadline.weight(.semibold))
                            Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("comments.mention.\(user.username)")
            }
        }
        .padding(.vertical, 4)
    }
}

// Une ligne de commentaire ou de réponse.
struct CommentRow: View {
    struct Actions {
        var openProfile: (String) -> Void
        var openHashtag: (String) -> Void
        var reply: () -> Void
        var like: () -> Void
        var dislike: () -> Void
    }

    // Retrait des réponses sous leur commentaire.
    static let replyIndent: CGFloat = 52

    let comment: VideoComment
    let isCreator: Bool
    let isDisliked: Bool
    let creatorAvatarURL: URL?
    let creatorName: String
    let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                actions.openProfile(comment.author.username)
            } label: {
                AvatarView(url: comment.author.avatarURL, name: comment.author.displayName, size: comment.isReply ? 28 : 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil de @\(comment.author.username)")
            VStack(alignment: .leading, spacing: 5) {
                header
                if isDisliked {
                    HStack(spacing: 4) {
                        Text("Tu n’aimes pas ce commentaire.").foregroundStyle(.secondary)
                        Button("Afficher", action: actions.dislike)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                } else {
                    CommentText(text: comment.content, onMention: actions.openProfile, onHashtag: actions.openHashtag)
                        .font(.body)
                    footer
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isDisliked { reactions }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment.\(comment.id)")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(comment.author.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if isCreator {
                Text("·").font(.subheadline).foregroundStyle(.secondary)
                Text("Créateur").font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 0.13, green: 0.6, blue: 0.75))
            }
        }
        .onTapGesture { actions.openProfile(comment.author.username) }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            date
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Répondre", action: actions.reply)
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("comment.reply")
            // « Aimé par l'auteur » : photo de l'auteur de la vidéo avec un cœur, comme TikTok.
            if comment.likedByAuthor {
                AvatarView(url: creatorAvatarURL, name: creatorName, size: 20)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .offset(x: 3, y: 2)
                    }
                    .accessibilityLabel("Aimé par l’auteur")
            }
        }
    }

    // Date courte, comme TikTok : relative la première semaine, puis « 25/09 » (avec l'année si elle diffère).
    @ViewBuilder
    private var date: some View {
        switch CommentRules.dateStyle(for: comment.createdAt, now: .now) {
        case .relative: Text.relative(comment.createdAt)
        case .dayMonth: Text(comment.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits))
        case .full: Text(comment.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year())
        }
    }

    // Cœur et compteur, puis « Je n'aime pas ».
    private var reactions: some View {
        let liked = comment.viewerLiked == true
        return HStack(spacing: 14) {
            Button(action: actions.like) {
                HStack(spacing: 4) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(liked ? Color.red : Color.secondary)
                    if comment.likesCount > 0 {
                        Text(comment.likesCount.formatted(.number.notation(.compactName)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(minWidth: 44, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liked ? "Je n’aime plus ce commentaire" : "J’aime ce commentaire")
            .accessibilityIdentifier("comment.like")
            Button(action: actions.dislike) {
                Image(systemName: "hand.thumbsdown")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Je n’aime pas ce commentaire")
            .accessibilityIdentifier("comment.dislike")
        }
        .padding(.top, 18)
    }
}

// « —— Afficher N réponses ⌄ » sous un commentaire ; une fois déplié, « Afficher N de plus » s'il en reste et « Masquer ⌃ ».
struct ThreadControlRow: View {
    let remaining: Int
    let isExpanded: Bool
    let isLoading: Bool
    let show: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Rectangle().fill(Color(.separator)).frame(width: 32, height: 1)
            if isLoading {
                ProgressView().controlSize(.small)
            } else if remaining > 0 {
                Button(action: show) {
                    Label(showTitle, systemImage: "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .accessibilityIdentifier("comment.showReplies")
            }
            if isExpanded {
                Button(action: hide) {
                    Label("Masquer", systemImage: "chevron.up")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .accessibilityIdentifier("comment.hideReplies")
            }
            Spacer()
        }
        .buttonStyle(.plain)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var showTitle: String {
        if isExpanded { return "Afficher \(remaining) de plus" }
        return remaining == 1 ? "Afficher 1 réponse" : "Afficher \(remaining) réponses"
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.caption2.weight(.bold))
        }
    }
}

// Texte d'un commentaire : mentions (ADR-060) et hashtags (ADR-049) cliquables, par des liens internes interceptés.
struct CommentText: View {
    let text: String
    let onMention: (String) -> Void
    let onHashtag: (String) -> Void

    // Bleu des mentions, comme TikTok.
    static let mentionColor = Color(red: 0.17, green: 0.36, blue: 0.72)

    var body: some View {
        Text(attributed)
            // Couleur des liens (mentions et hashtags).
            .tint(Self.mentionColor)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if let username = ProfileLink.username(from: url) {
                        onMention(username)
                        return .handled
                    }
                    if let name = HashtagLink.name(from: url) {
                        onHashtag(name)
                        return .handled
                    }
                    return .discarded
                })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        for occurrence in MentionRules.occurrences(in: text) {
            guard let range = Range(occurrence.range, in: result) else { continue }
            result[range].link = ProfileLink.url(for: occurrence.username)
            result[range].foregroundColor = Self.mentionColor
            result[range].inlinePresentationIntent = .stronglyEmphasized
        }
        for occurrence in HashtagRules.occurrences(in: text) {
            guard let range = Range(occurrence.range, in: result) else { continue }
            result[range].link = HashtagLink.url(for: occurrence.name)
            result[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}
