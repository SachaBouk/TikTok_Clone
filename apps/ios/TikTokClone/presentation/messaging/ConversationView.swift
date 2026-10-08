import SwiftUI

// Fil d'une conversation : messages (texte, vidéo partagée), « Vu », « en train d'écrire », champ de saisie.
// Demande reçue : accepter ou refuser (ou répondre, ce qui l'accepte). Appui long sur un message : copier,
// retirer le sien (pour les deux), signaler celui de l'autre (ADR-038). Message non envoyé : toucher pour réessayer,
// copier ou supprimer (ADR-044).
struct ConversationView: View {
    @State private var viewModel: ConversationViewModel
    let container: AppContainer
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDecline = false
    @State private var retracting: DirectMessage?
    @State private var reportTarget: ReportTarget?
    @State private var isOnScreen = false
    // Ouvert par un bouton : un lien de navigation par valeur ne fonctionne pas dans un écran lui-même poussé
    // par `navigationDestination(item:)` (boîte de réception, demandes).
    @State private var openedProfile: ProfileRoute?
    @FocusState private var isComposing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ConversationViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
    }

    var body: some View {
        content
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(item: $openedProfile) { route in
                ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.state == .loaded { bottomBar }
            }
            .task { await viewModel.load() }
            // Marquer lu seulement ce qui est réellement affiché.
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onChange(of: isOnScreen && isTabActive && scenePhase == .active, initial: true) { _, visible in
                viewModel.setVisible(visible)
            }
            .onChange(of: viewModel.isClosed) { _, closed in
                if closed { dismiss() }
            }
            .reportSheet($reportTarget, container: container)
            .confirmationDialog("Supprimer la conversation ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await viewModel.delete() } }
            } message: {
                Text("Elle disparaît pour toi seulement : @\(viewModel.username) garde vos messages.")
            }
            .confirmationDialog("Refuser la demande ?", isPresented: $isConfirmingDecline, titleVisibility: .visible) {
                Button("Refuser", role: .destructive) { Task { await viewModel.decline() } }
            } message: {
                Text("Elle disparaît de tes demandes. @\(viewModel.username) n’en sera pas informé(e).")
            }
            .confirmationDialog(
                "Retirer ce message ?",
                isPresented: Binding(
                    get: { retracting != nil },
                    set: { if !$0 { retracting = nil } }
                ), titleVisibility: .visible, presenting: retracting
            ) { message in
                Button("Retirer", role: .destructive) { Task { await viewModel.retract(message) } }
            } message: { _ in
                Text("Il sera retiré pour vous deux.")
            }
            .alert(
                "Messages",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .accessibilityIdentifier("conversation")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Conversation indisponible", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            messageList
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.hasOlderMessages {
                        ProgressView()
                            .padding()
                            .onAppear {
                                Task {
                                    // Garder à l'écran le message qui était en tête.
                                    if let anchor = await viewModel.loadOlder() { proxy.scrollTo(anchor, anchor: .top) }
                                }
                            }
                    } else if let conversation = viewModel.conversation {
                        ConversationHeader(user: conversation.participant) {
                            openedProfile = ProfileRoute(username: conversation.participant.username)
                        }
                    }
                    let ownID = viewModel.ownID
                    let timestamped = viewModel.timestampedIDs
                    let seenID = viewModel.seenMessageID
                    ForEach(viewModel.messages) { message in
                        let isOwn = message.senderID == ownID
                        if timestamped.contains(message.id) {
                            Text(message.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        MessageBubble(message: message, isOwn: isOwn) { videoID in
                            container.router.presentedVideo = AppRouter.VideoRoute(id: videoID)
                        }
                        .contextMenu {
                            if !message.content.isEmpty {
                                Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                            }
                            if isOwn {
                                Button("Retirer", systemImage: "trash", role: .destructive) { retracting = message }
                            } else {
                                Button("Signaler", systemImage: "flag") { reportTarget = .message(id: message.id) }
                            }
                        }
                        .id(message.id)
                        if message.id == seenID {
                            Text("Vu")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .accessibilityIdentifier("conversation.seen")
                        }
                    }
                    let canRetry = viewModel.conversation?.canSend == true
                    ForEach(viewModel.pending) { outgoing in
                        OutgoingBubble(
                            message: outgoing,
                            canRetry: canRetry,
                            retry: { Task { await viewModel.retry(outgoing) } },
                            discard: { viewModel.discard(outgoing) }
                        )
                    }
                    if viewModel.isOtherTyping {
                        TypingBubble()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.id) { scrollToBottom(proxy) }
            .onChange(of: viewModel.pending.map(\.id)) { scrollToBottom(proxy) }
            .onChange(of: viewModel.isOtherTyping) { scrollToBottom(proxy) }
            .onChange(of: isComposing) { scrollToBottom(proxy) }
        }
    }

    private static let bottomID = "conversation.bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if viewModel.isRequestReceived {
                RequestBar(
                    username: viewModel.username,
                    accept: { Task { await viewModel.accept() } },
                    decline: { isConfirmingDecline = true }
                )
            }
            if let notice = viewModel.conversation?.composerNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("conversation.notice")
            }
            if viewModel.conversation?.canSend == true {
                composer
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var composer: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isComposing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("conversation.field")
                // Rafraîchi chaque seconde pour lever la limite d'envoi à l'heure dite.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .disabled(!viewModel.canSend(at: context.date))
                    .accessibilityLabel("Envoyer")
                    .accessibilityIdentifier("conversation.send")
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let seconds = viewModel.secondsBeforeSending(at: context.date) {
                    Text("Trop de messages envoyés. Réessaie dans \(seconds) s.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("conversation.rateLimit")
                } else if viewModel.draft.count > MessageRules.maxLength - 100 {
                    Text("\(viewModel.draft.count)/\(MessageRules.maxLength)")
                        .font(.caption)
                        .foregroundStyle(viewModel.draft.count > MessageRules.maxLength ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Voir le profil", systemImage: "person.crop.circle") { openedProfile = ProfileRoute(username: viewModel.username) }
                if viewModel.conversation != nil, !viewModel.isRequestReceived {
                    Button("Supprimer la conversation", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("conversation.menu")
        }
    }
}

// En tête d'une conversation dont tout l'historique est chargé : qui est l'autre participant.
private struct ConversationHeader: View {
    let user: UserSummary
    let openProfile: () -> Void

    var body: some View {
        Button(action: openProfile) {
            VStack(spacing: 6) {
                AvatarView(url: user.avatarURL, name: user.displayName, size: 72)
                Text(user.displayName).font(.headline)
                Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

// Demande reçue : accepter ou refuser. Répondre l'accepte aussi.
private struct RequestBar: View {
    let username: String
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(
                "@\(username) veut t’envoyer un message. Accepte pour discuter librement ; il ou elle ne saura pas que tu as lu sa demande d’ici là."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            HStack {
                Button("Refuser", role: .destructive, action: decline)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("conversation.decline")
                Button("Accepter", action: accept)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("conversation.accept")
            }
        }
    }
}

// Un message : vidéo partagée (miniature, auteur) et/ou texte, à droite pour les siens.
private struct MessageBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    let openVideo: (String) -> Void

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if let story = message.story {
                RepliedStoryCard(story: story, isOwn: isOwn)
            }
            if let video = message.sharedVideo {
                SharedVideoCard(video: video, open: openVideo)
            }
            if !message.content.isEmpty {
                TextBubble(text: message.content, isOwn: isOwn)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}

// Message écrit ici, pas encore accepté (ADR-044) : « Envoi… » estompé, ou « Non envoyé » avec un menu natif.
private struct OutgoingBubble: View {
    let message: OutgoingMessage
    // Faux si la conversation ne permet plus d'écrire (blocage, demande épuisée) : copier ou supprimer seulement.
    let canRetry: Bool
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        switch message.state {
        case .sending:
            TextBubble(text: message.content, isOwn: true)
                .opacity(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Envoi : \(message.content)")
        case .failed:
            Menu {
                if canRetry { Button("Réessayer", systemImage: "arrow.clockwise", action: retry) }
                Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                Button("Supprimer", systemImage: "trash", role: .destructive, action: discard)
            } label: {
                VStack(alignment: .trailing, spacing: 4) {
                    // Le « ! » à droite : la bulle occupe un cadre de 280 pt, aligné à droite.
                    HStack(spacing: 6) {
                        TextBubble(text: message.content, isOwn: true)
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Text(canRetry ? "Non envoyé · Toucher pour réessayer" : "Non envoyé")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Non envoyé : \(message.content)")
            .accessibilityIdentifier("conversation.failedMessage")
        }
    }
}

struct TextBubble: View {
    let text: String
    let isOwn: Bool

    var body: some View {
        Text(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOwn ? .white : .primary)
            .background(isOwn ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            .textSelection(.enabled)
    }
}

// Vidéo partagée : miniature 9:16 et auteur ; « Vidéo indisponible » si elle a été supprimée depuis.
private struct SharedVideoCard: View {
    let video: SharedVideo
    let open: (String) -> Void

    var body: some View {
        if video.available {
            Button {
                open(video.id)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: nil)
                    if let author = video.author {
                        Text("@\(author.username)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vidéo de @\(video.author?.username ?? "")")
            .accessibilityIdentifier("conversation.sharedVideo")
        } else {
            Label("Vidéo indisponible", systemImage: "video.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Réponse à une story (ADR-051) : sa miniature tant qu'elle est en ligne, puis « Story expirée ».
private struct RepliedStoryCard: View {
    let story: RepliedStory
    let isOwn: Bool

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            Text(isOwn ? "Tu as répondu à sa story" : "A répondu à ta story")
                .font(.caption)
                .foregroundStyle(.secondary)
            if story.available, let thumbnailURL = story.thumbnailURL {
                VideoGridCell(thumbnailURL: thumbnailURL, image: nil, views: nil)
                    .frame(width: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if story.mediaType == .video {
                            Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).shadow(radius: 2).padding(6)
                        }
                    }
                    .accessibilityLabel("Story")
            } else {
                Label("Story expirée", systemImage: "clock.badge.xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conversation.repliedStory")
    }
}

// « En train d'écrire » : trois points animés.
private struct TypingBubble: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 7, height: 7)
                        .opacity(index == step ? 1 : 0.35)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityLabel("En train d’écrire")
        .accessibilityIdentifier("conversation.typing")
    }
}
