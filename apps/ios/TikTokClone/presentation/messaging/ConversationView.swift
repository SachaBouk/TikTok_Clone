import SwiftUI

// Fil d'une conversation : messages (texte, vidéo partagée), « Vu », « en train d'écrire », champ de saisie.
// Demande reçue : accepter ou refuser (ou répondre, ce qui l'accepte). Appui long sur un message : copier,
// retirer le sien (pour les deux), signaler celui de l'autre (ADR-038). Message non envoyé : toucher pour réessayer,
// copier ou supprimer (ADR-044). Groupe (ADR-059) : nom de l'expéditeur au-dessus de ses messages, lignes d'événement,
// « Vu par … », « Inès écrit… », réglages du groupe.
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
    // Collection partagée (ADR-072), ouverte de la même façon.
    @State private var openedCollection: CollectionRoute?
    @State private var showsGroupSettings = false
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
            .navigationDestination(item: $openedCollection) { route in
                CollectionDetailView(model: container.makeCollectionDetailModel(route), container: container)
            }
            .navigationDestination(isPresented: $showsGroupSettings) {
                GroupSettingsView(viewModel: viewModel, container: container)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.state == .loaded { bottomBar }
            }
            .task { await viewModel.load() }
            // Marquer lu seulement ce qui est réellement affiché. Quitté ou supprimé depuis les réglages du groupe (ADR-059) :
            // cachée sous eux, la conversation n'a pas vu le changement ; elle se ferme en réapparaissant.
            .onAppear {
                isOnScreen = true
                // Pendant l'animation de retour, `dismiss` serait ignoré : un instant après.
                if viewModel.isClosed {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        dismiss()
                    }
                }
            }
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
                Text(
                    viewModel.group != nil
                        ? "Les messages disparaissent pour toi seulement ; tu restes dans le groupe."
                        : "Elle disparaît pour toi seulement : @\(viewModel.username) garde vos messages.")
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
                Text(viewModel.group != nil ? "Il sera retiré pour tous les membres." : "Il sera retiré pour vous deux.")
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
                    } else if let group = viewModel.group {
                        GroupHeader(group: group, ownID: viewModel.ownID) { showsGroupSettings = true }
                    } else if let participant = viewModel.conversation?.participant {
                        ConversationHeader(user: participant) {
                            openedProfile = ProfileRoute(username: participant.username)
                        }
                    }
                    let ownID = viewModel.ownID
                    let timestamped = viewModel.timestampedIDs
                    let seen = viewModel.seen
                    let inGroup = viewModel.group != nil
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        let isOwn = message.senderID == ownID
                        if timestamped.contains(message.id) {
                            Text(message.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                // L'heure est dite dans chaque bulle (ADR-076).
                                .accessibilityHidden(true)
                        }
                        let seenLabel = message.id == seen?.messageID ? seen?.label : nil
                        let spoken = ConversationSpeech.label(
                            of: message, ownID: ownID, participant: viewModel.conversation?.participant, inGroup: inGroup, seen: seenLabel)
                        if let event = message.event {
                            Text(event.text(actor: message.sender, ownID: ownID))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .id(message.id)
                                .accessibilityLabel(spoken)
                                .accessibilityIdentifier("conversation.groupEvent")
                        } else {
                            // Groupe : photo et nom de l'expéditeur au premier message d'une suite.
                            let previous = index > 0 ? viewModel.messages[index - 1] : nil
                            let showsSender = inGroup && !isOwn && (previous?.senderID != message.senderID || previous?.event != nil)
                            MessageBubble(
                                message: message, isOwn: isOwn, sender: inGroup && !isOwn ? message.sender : nil, showsSender: showsSender,
                                spokenLabel: spoken
                            ) {
                                videoID in
                                container.router.presentedVideo = AppRouter.VideoRoute(id: videoID)
                            } openLive: { liveID in
                                container.router.openLive(liveID, source: .message)
                            } openProfile: { username in
                                openedProfile = ProfileRoute(username: username)
                            } openCollection: { collection in
                                openedCollection = CollectionRoute(id: collection.id, preview: collection)
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
                            // Les mêmes choix que l'appui long, dans le rotor « Actions » de VoiceOver (ADR-076).
                            .accessibilityActions {
                                if !message.content.isEmpty {
                                    Button("Copier") {
                                        UIPasteboard.general.string = message.content
                                        Accessibility.announce("Copié")
                                    }
                                }
                                if isOwn {
                                    Button("Retirer") { retracting = message }
                                } else {
                                    Button("Signaler") { reportTarget = .message(id: message.id) }
                                }
                            }
                            .id(message.id)
                        }
                        if message.id == seen?.messageID, let label = seen?.label {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                // Dit avec la bulle (« …, vu »).
                                .accessibilityHidden(true)
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
                        VStack(alignment: .leading, spacing: 4) {
                            if let label = viewModel.typingLabel {
                                Text(label).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("conversation.typingLabel")
                            }
                            TypingBubble()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(viewModel.typingSpeech)
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
            // « Inès écrit… » dit une fois par épisode (ADR-076), pas à chaque événement reçu.
            .onChange(of: viewModel.isOtherTyping) { _, typing in
                if typing { Accessibility.announce(viewModel.typingSpeech) }
            }
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
                if viewModel.group != nil {
                    Button("Réglages du groupe", systemImage: "person.2") { showsGroupSettings = true }
                } else {
                    Button("Voir le profil", systemImage: "person.crop.circle") { openedProfile = ProfileRoute(username: viewModel.username) }
                }
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
                Text(user.displayName).font(.headline).plusBadge(user.isPlus, size: 14)
                Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profil de \(user.displayName), @\(user.username)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openProfile() }
    }
}

// En tête d'un groupe dont tout l'historique est chargé : photos, nom, membres ; toucher ouvre les réglages.
private struct GroupHeader: View {
    let group: GroupChat
    let ownID: String?
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            VStack(spacing: 6) {
                ConversationAvatar(users: Array(group.others(ownID: ownID).prefix(2)), size: 72)
                Text(group.title(ownID: ownID)).font(.headline).multilineTextAlignment(.center)
                Text("\(group.members.count) membres · Groupe privé").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title(ownID: ownID)), \(SpokenText.count(group.members.count, "membre", "membres")), groupe privé")
        .accessibilityHint("Ouvre les réglages du groupe")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openSettings() }
        .accessibilityIdentifier("conversation.groupHeader")
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
                    .accessibilityLabel("Refuser la demande de @\(username)")
                    .accessibilityIdentifier("conversation.decline")
                Button("Accepter", action: accept)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Accepter la demande de @\(username)")
                    .accessibilityIdentifier("conversation.accept")
            }
        }
    }
}

// Un message : vidéo partagée (miniature, auteur) et/ou texte, à droite pour les siens.
private struct MessageBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    // Groupe : l'expéditeur d'un message d'un autre (photo à gauche, nom au premier message d'une suite).
    var sender: UserSummary? = nil
    var showsSender = false
    // Phrase lue par VoiceOver : la bulle entière est un seul élément (ADR-076).
    var spokenLabel = ""
    let openVideo: (String) -> Void
    let openLive: (String) -> Void
    var openProfile: (String) -> Void = { _ in }
    var openCollection: (VideoCollection) -> Void = { _ in }

    var body: some View {
        bubble
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(primaryAction == nil ? [] : .isButton)
            .modifier(OptionalDefaultAction(action: primaryAction))
            .accessibilityActions {
                if let sender { Button("Profil de \(sender.displayName)") { openProfile(sender.username) } }
            }
    }

    // Carte à ouvrir en touchant deux fois la bulle (vidéo, live, profil, collection encore disponibles).
    private var primaryAction: (() -> Void)? {
        if let video = message.sharedVideo, video.available { return { openVideo(video.id) } }
        if let live = message.live, live.available { return { openLive(live.id) } }
        if let user = message.profile?.user { return { openProfile(user.username) } }
        if let collection = message.collection?.collection { return { openCollection(collection) } }
        return nil
    }

    @ViewBuilder
    private var bubble: some View {
        if let sender {
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    openProfile(sender.username)
                } label: {
                    AvatarView(url: sender.avatarURL, name: sender.displayName, size: 28)
                }
                .buttonStyle(.plain)
                .opacity(showsSender ? 1 : 0)
                .accessibilityHidden(!showsSender)
                VStack(alignment: .leading, spacing: 2) {
                    if showsSender {
                        Text(sender.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    bubbles
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            bubbles
        }
    }

    private var bubbles: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if let story = message.story {
                RepliedStoryCard(story: story, isOwn: isOwn)
            }
            if let video = message.sharedVideo {
                SharedVideoCard(video: video, open: openVideo)
            }
            if let live = message.live {
                SharedLiveCard(live: live, open: openLive)
            }
            if let profile = message.profile {
                SharedProfileCard(profile: profile, open: openProfile)
            }
            if let collection = message.collection {
                SharedCollectionCard(shared: collection, open: openCollection)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ConversationSpeech.outgoingLabel(content: message.content, state: .sending))
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
            .accessibilityLabel(ConversationSpeech.outgoingLabel(content: message.content, state: .failed))
            .accessibilityHint("Touche deux fois pour les options")
            .accessibilityActions {
                if canRetry { Button("Réessayer", action: retry) }
                Button("Copier") {
                    UIPasteboard.general.string = message.content
                    Accessibility.announce("Copié")
                }
                Button("Supprimer", action: discard)
            }
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

// Live partagé (ADR-053) : auteur et titre, « EN DIRECT » ; « Live terminé » une fois fini (ou masqué au lecteur).
private struct SharedLiveCard: View {
    let live: SharedLive
    let open: (String) -> Void

    var body: some View {
        if live.available {
            Button {
                open(live.id)
            } label: {
                HStack(spacing: 10) {
                    if let host = live.host { AvatarView(url: host.avatarURL, name: host.displayName, size: 44) }
                    VStack(alignment: .leading, spacing: 4) {
                        LiveBadge()
                        Text(live.host.map { "@\($0.username)" } ?? "Live").font(.subheadline.bold())
                        if let title = live.title { Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .padding(12)
                .frame(width: 240, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live de @\(live.host?.username ?? "")")
            .accessibilityIdentifier("conversation.sharedLive")
        } else {
            Label("Live terminé", systemImage: "dot.radiowaves.left.and.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Profil partagé (ADR-069) : photo, nom, @pseudo et « Voir le profil » ; compte supprimé ou masqué : « Profil indisponible ».
private struct SharedProfileCard: View {
    let profile: SharedProfile
    let open: (String) -> Void

    var body: some View {
        if let user = profile.user {
            Button {
                open(user.username)
            } label: {
                VStack(spacing: 6) {
                    AvatarView(url: user.avatarURL, name: user.displayName, size: 64)
                    Text(user.displayName).font(.subheadline.bold()).lineLimit(1)
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("Voir le profil")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 4)
                }
                .padding(14)
                .frame(width: 200)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil de @\(user.username)")
            .accessibilityIdentifier("conversation.sharedProfile")
        } else {
            Label("Profil indisponible", systemImage: "person.crop.circle.badge.xmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Collection partagée (ADR-072) : image, nom, « N publications · @pseudo » et « Voir la collection » ; supprimée, redevenue
// privée ou masquée : « Collection indisponible ».
private struct SharedCollectionCard: View {
    let shared: SharedCollection
    let open: (VideoCollection) -> Void

    var body: some View {
        if let collection = shared.collection {
            Button {
                open(collection)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    CollectionCard(collection: collection)
                    Text("\(collection.countLabel) · @\(collection.owner.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("Voir la collection")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(10)
                .frame(width: 200)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collection \(collection.name) de @\(collection.owner.username)")
            .accessibilityIdentifier("conversation.sharedCollection")
        } else {
            Label("Collection indisponible", systemImage: "bookmark.slash")
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

// Action par défaut (toucher deux fois) seulement quand il y a quelque chose à ouvrir.
private struct OptionalDefaultAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction { action() }
        } else {
            content
        }
    }
}

// Pastille « EN DIRECT » d'une carte de live partagé (ADR-053, anciens lives).
private struct LiveBadge: View {
    var body: some View {
        Text("EN DIRECT")
            .font(.caption2.weight(.heavy))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}
