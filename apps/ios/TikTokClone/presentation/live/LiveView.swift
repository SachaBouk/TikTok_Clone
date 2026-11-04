import SwiftUI
import UIKit

// Écran et salle d'un live, créés ensemble à l'ouverture (AppContainer.makeLiveRoom).
struct LiveRoomSetup {
    let model: LiveRoomModel
    let room: LiveKitRoom
}

extension View {
    // Live de `router.presentedLive` (ADR-053), présenté à la racine, par-dessus tout le reste.
    func livePresenter(_ container: AppContainer) -> some View {
        modifier(LivePresenter(container: container))
    }
}

private struct LivePresenter: ViewModifier {
    let container: AppContainer
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        @Bindable var router = container.router
        @Bindable var session = session
        content.fullScreenCover(item: $router.presentedLive) { route in
            LiveScreen(route: route, container: container)
                // La connexion doit pouvoir s'ouvrir par-dessus le live (écrire, cœurs, cadeaux en invité).
                .sheet(isPresented: $session.isPresentingSignIn) {
                    AuthFlowView(container: container)
                }
                .environment(session)
        }
    }
}

// Un plein écran créé dans le contenu d'un `fullScreenCover` est recréé à chaque mise à jour : la salle et son modèle
// sont créés une fois, à l'apparition. Lives à faire défiler (icône « LIVE », ADR-066) : `LiveFeedScreen`.
private struct LiveScreen: View {
    let route: AppRouter.LiveRoute
    let container: AppContainer
    @State private var setup: LiveRoomSetup?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch route.content {
            case .discover:
                LiveFeedScreen(container: container)
            case .room(let mode):
                if let setup {
                    LiveView(model: setup.model, room: setup.room, container: container)
                }
                Color.clear.onAppear {
                    if setup == nil { setup = container.makeLiveRoom(mode: mode) }
                }
            }
        }
    }
}

// Écran d'un live, façon TikTok (ADR-066) : pastille de l'auteur en haut (photo, nom, j'aime, « + Suivre »), spectateurs,
// chat avec ses lignes d'événement, barre du bas (« Commenter », Rose, Cadeau, Partager), j'aime en touchant l'écran.
struct LiveView: View {
    let model: LiveRoomModel
    let room: LiveKitRoom
    let container: AppContainer
    // Dans les lives à faire défiler : × sur l'écran de fin et « Balaie vers le haut pour le live suivant ».
    var hasNextLive = false
    var isInFeed = false
    // Marges de la zone de sécurité, données par les lives à faire défiler (leur `ScrollView` l'ignore).
    var insets = EdgeInsets()
    // Lives à faire défiler : la saisie est affichée par l'écran des lives, au-dessus du clavier (les pages, elles,
    // ignorent le clavier pour garder leur taille). Nil : la saisie est dans cet écran.
    var feedComposer: Binding<Bool>? = nil
    @State private var isConfirmingEnd = false
    @State private var isSharing = false
    @State private var chosenForMessage = false
    // Envoi par message : le modèle reste après la fermeture, pour savoir si un message est parti.
    @State private var sendByMessage: SendVideoViewModel?
    @State private var isSendingByMessage = false
    @State private var isGiving = false
    @State private var isShowingHost = false
    @State private var showsComposer = false
    @State private var reportTarget: ReportTarget?
    @FocusState private var isComposing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .environment(\.colorScheme, .dark)
            .task { await model.start() }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                Task { await model.leave() }
            }
            .sheet(
                isPresented: $isSharing,
                onDismiss: {
                    if chosenForMessage { openSendByMessage() }
                    chosenForMessage = false
                }
            ) {
                if let live = model.live {
                    ActivityShareSheet(items: LiveShareContent(live: live).activityItems, allowsSendByMessage: container.session.isSignedIn) {
                        outcome in
                        switch outcome {
                        case .shared:
                            container.analytics.track(.liveShared(byMessage: false))
                            Task { await model.shared() }
                        // Même piège que pour une vidéo : UIKit ferme parfois la feuille avant ce gestionnaire.
                        case .sendByMessage:
                            container.analytics.track(.liveShared(byMessage: true))
                            if isSharing { chosenForMessage = true } else { openSendByMessage() }
                        case .cancelled: break
                        }
                        isSharing = false
                    }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
                }
            }
            .sheet(
                isPresented: $isSendingByMessage,
                onDismiss: {
                    // Un envoi par message est aussi un partage : annoncé dans la salle.
                    if sendByMessage?.deliveries.values.contains(.sent) == true { Task { await model.shared() } }
                    sendByMessage = nil
                }
            ) {
                if let sendByMessage {
                    SendVideoView(viewModel: sendByMessage)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isGiving) {
                if let live = model.live {
                    // Le cadeau envoyé s'affiche dans la salle, pour tous : pas d'animation propre à l'expéditeur.
                    GiftSheet(viewModel: container.makeGiftSheetViewModel(target: .live(id: live.id, host: live.host)), container: container) { _ in
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $isShowingHost) {
                if let live = model.live {
                    LiveHostSheet(model: container.makeLiveHostModel(username: live.host.username), host: live.host, container: container) {
                        guard container.session.isSignedIn else { return container.session.requestSignIn() }
                        reportTarget = .live(id: live.id)
                    }
                    .presentationDetents([.medium])
                    .presentationCornerRadius(16)
                    .presentationBackground(.white)
                }
            }
            .reportSheet($reportTarget, container: container)
            // Rose sans assez de jetons : la feuille des cadeaux, avec « Recharger ».
            .onChange(of: model.needsRecharge) { _, needed in
                if needed {
                    model.needsRecharge = false
                    isGiving = true
                }
            }
            .alert(
                "Action impossible",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    private func openSendByMessage() {
        guard let live = model.live else { return }
        sendByMessage = container.makeSendLiveViewModel(live: live)
        isSendingByMessage = true
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .connecting:
            LiveLoadingView(host: model.live?.host)
                .overlay(alignment: .topTrailing) { closeButton(confirm: false).padding(.horizontal, 12).padding(.top, insets.top) }
        case .failed(let message):
            ContentUnavailableView {
                Label("Live indisponible", systemImage: "video.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        case .ended(let live, let reason):
            if model.isHost {
                LiveEndedView(live: live, reason: reason, isHost: true) { dismiss() }
            } else {
                LiveFeedbackView(
                    model: model, live: live ?? model.live, reason: reason, hasNextLive: hasNextLive, isInFeed: isInFeed, insets: insets
                ) { dismiss() }
            }
        case .live:
            liveContent
        }
    }

    private var liveContent: some View {
        ZStack {
            LiveVideoView(room: room)
                .ignoresSafeArea()
                .overlay {
                    if !model.hasVideo && !model.isHost { LiveLoadingView(host: model.live?.host) }
                }
            // La vue vidéo de LiveKit garde les touchers : une couche transparente au-dessus reçoit les j'aime (ADR-066),
            // ou ferme le clavier.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named(Self.screenSpace)).onEnded { value in
                        if isComposing {
                            isComposing = false
                        } else if let feedComposer, feedComposer.wrappedValue {
                            feedComposer.wrappedValue = false
                        } else {
                            model.like(x: value.location.x, y: value.location.y)
                        }
                    }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Envoyer un j’aime")
                .accessibilityIdentifier("live.likeArea")
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom).frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).frame(height: 360)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(spacing: 8) {
                header.padding(.horizontal, 12)
                Spacer()
                VStack(spacing: 8) {
                    gifts
                    chat
                }
                .padding(.horizontal, 12)
                if showsComposer {
                    composer
                } else {
                    bottomBar.padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
            .padding(.top, insets.top)
            .padding(.bottom, showsComposer ? 0 : insets.bottom)
            LiveTapHeartsView(model: model)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            FloatingHeartsView(model: model)
                .allowsHitTesting(false)
        }
        .coordinateSpace(.named(Self.screenSpace))
        .onChange(of: isComposing) { _, composing in
            if !composing { showsComposer = false }
        }
        .confirmationDialog("Terminer le live ?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("Terminer le live", role: .destructive) { Task { await model.end() } }
        } message: {
            Text("Les spectateurs seront prévenus. Le live ne sera pas enregistré.")
        }
    }

    private static let screenSpace = "live.screen"

    // ─── En-tête : pastille de l'auteur, spectateurs, fermer ───

    private var header: some View {
        HStack(spacing: 8) {
            if let live = model.live { hostPill(live.host) }
            Spacer(minLength: 4)
            if model.isHost {
                Button("Changer de caméra", systemImage: "arrow.triangle.2.circlepath.camera") { Task { await model.switchCamera() } }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            Label("\(model.viewersCount)", systemImage: "person.fill")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.black.opacity(0.35), in: Capsule())
                .foregroundStyle(.white)
                .accessibilityLabel("\(model.viewersCount) spectateurs")
            closeButton(confirm: model.isHost)
        }
    }

    // Photo, nom et j'aime du live ; « Tu as envoyé N j'aime » quelques secondes après ses propres touchers.
    private func hostPill(_ host: UserSummary) -> some View {
        let follows = container.videoInteractions.isFollowing(host.id, loaded: model.followsHost)
        let showsFollow = !model.isHost && !follows && container.session.profile?.id != host.id
        return HStack(spacing: 8) {
            Button {
                isShowingHost = true
            } label: {
                HStack(spacing: 8) {
                    AvatarView(url: host.avatarURL, name: host.displayName, size: 36)
                    if model.showsMyLikes {
                        Text("Tu as envoyé \(model.myLikes) j’aime")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .padding(.trailing, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(host.displayName).font(.subheadline.bold()).lineLimit(1)
                            Label(model.heartsTotal.formatted(.number.notation(.compactName)), systemImage: "heart.fill")
                                .font(.caption2.weight(.semibold))
                                .labelStyle(LivePillLabelStyle())
                                .opacity(0.85)
                        }
                        .frame(maxWidth: 130, alignment: .leading)
                        .padding(.trailing, showsFollow ? 0 : 12)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auteur du live : \(host.displayName)")
            .accessibilityIdentifier("live.host")
            if showsFollow && !model.showsMyLikes {
                Button {
                    Task { _ = await container.videoInteractions.setFollowing(host, active: true, wasFollowing: false) }
                } label: {
                    Label("Suivre", systemImage: "plus")
                        .font(.subheadline.bold())
                        .labelStyle(LivePillLabelStyle())
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.brandPink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .accessibilityIdentifier("live.follow")
            }
        }
        .padding(3)
        .foregroundStyle(.white)
        .background(model.showsMyLikes ? Color.brandPink : Color.black.opacity(0.35), in: Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.showsMyLikes)
    }

    private func closeButton(confirm: Bool) -> some View {
        Button(confirm ? "Terminer le live" : "Fermer", systemImage: "xmark") {
            if confirm { isConfirmingEnd = true } else { dismiss() }
        }
        .labelStyle(.iconOnly)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .shadow(radius: 2)
        .disabled(model.isEnding)
        .accessibilityIdentifier("live.close")
    }

    // ─── Cadeaux reçus, chat ───

    private var gifts: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.gifts) { event in
                HStack(spacing: 8) {
                    AvatarView(url: event.sender.avatarURL, name: event.sender.displayName, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.sender.displayName).font(.caption.bold())
                        Text("a envoyé \(event.gift.name)").font(.caption)
                    }
                    Text(event.gift.emoji).font(.largeTitle)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(.black.opacity(0.4), in: Capsule())
                .foregroundStyle(.white)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring, value: model.gifts)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.entries) { entry in
                        switch entry {
                        case .message(let message):
                            LiveChatRow(message: message, isHost: message.user.id == model.live?.host.id)
                                .contextMenu {
                                    Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                                    if model.canDelete(message) {
                                        Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await model.delete(message) } }
                                    }
                                }
                                .id(entry.id)
                        case .event(let event):
                            LiveChatEventRow(event: event).id(entry.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 260)
            .defaultScrollAnchor(.bottom)
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
            .onChange(of: model.entries.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    // ─── Barre du bas et saisie ───

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                guard container.session.isSignedIn else { return container.session.requestSignIn() }
                if let feedComposer { feedComposer.wrappedValue = true } else { showsComposer = true }
            } label: {
                HStack {
                    Text("Commenter").foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 4)
                    Image(systemName: "face.smiling").font(.title3).foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.comment")
            if !model.isHost {
                barButton(title: "Rose", emoji: "🌹") { Task { await model.sendRose() } }
                    .disabled(model.isSendingRose)
                    .accessibilityIdentifier("live.rose")
                barButton(title: "Cadeau", emoji: "🎁") {
                    if container.session.isSignedIn { isGiving = true } else { container.session.requestSignIn() }
                }
                .accessibilityIdentifier("live.gift")
            }
            barButton(title: "Partager", systemImage: "arrowshape.turn.up.right") { isSharing = true }
                .accessibilityIdentifier("live.share")
        }
    }

    private func barButton(title: String, emoji: String? = nil, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Group {
                    if let emoji {
                        Text(emoji).font(.system(size: 26))
                    } else if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 24, weight: .medium))
                    }
                }
                .frame(height: 30)
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    private var composer: some View {
        LiveComposer(model: model, isFocused: $isComposing)
    }
}

// Saisie d'un commentaire, au-dessus du clavier, comme TikTok : champ gris sur fond blanc, flèche grise (rouge une fois
// du texte écrit). Sous la barre, jusqu'en bas de l'écran, le gris du clavier : ses coins arrondis (iOS 26) ne laissent
// voir ni le live ni de bord.
// Focalisée à l'apparition ; le clavier fermé la retire (`isFocused` faux).
struct LiveComposer: View {
    // Fond du clavier système clair (relevé sur une capture).
    static let keyboardGray = Color(red: 231 / 255, green: 232 / 255, blue: 236 / 255)

    let model: LiveRoomModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                TextField(
                    "Commenter", text: Binding(get: { model.draft }, set: { model.draft = String($0.prefix(LiveRules.maxMessageLength)) }),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
                .accessibilityIdentifier("live.message")
                Image(systemName: "face.smiling").font(.title3).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            Button("Envoyer", systemImage: model.canSend ? "paperplane.fill" : "paperplane") { Task { await model.send() } }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(model.canSend ? Color.brandPink : Color(.systemGray2))
                .disabled(!model.canSend)
                .accessibilityIdentifier("live.send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            ZStack(alignment: .top) {
                Self.keyboardGray.ignoresSafeArea(.all, edges: .bottom)
                Color.white
            }
        }
        .environment(\.colorScheme, .light)
        .onAppear { isFocused.wrappedValue = true }
    }
}

// Icône et texte serrés (pastille de l'auteur).
private struct LivePillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

// En attendant l'image : photo floutée de l'auteur et les deux points rose et cyan (ADR-066).
struct LiveLoadingView: View {
    let host: UserSummary?

    var body: some View {
        ZStack {
            Color.black
            if let host {
                AvatarView(url: host.avatarURL, name: host.displayName, size: 1100)
                    .blur(radius: 50)
                    .overlay(Color.black.opacity(0.3))
            }
            DotsLoader(size: 14)
        }
        .ignoresSafeArea()
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Connexion au live…")
    }
}

// Message du chat, comme TikTok : photo, pseudo en gris, texte dessous. L'auteur du live est marqué.
private struct LiveChatRow: View {
    let message: LiveChatMessage
    let isHost: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: message.user.avatarURL, name: message.user.displayName, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(message.user.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        .plusBadge(message.user.isPlus, size: 13)
                    if isHost {
                        Text("Créateur")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.brandPink.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                    }
                }
                Text(message.content).font(.subheadline).foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
}

// Ligne d'événement du chat (ADR-066) : « Inès a rejoint », « a aimé le LIVE », « a partagé le LIVE ».
private struct LiveChatEventRow: View {
    let event: LiveChatEvent

    private var symbol: String {
        switch event.kind {
        case .joined: "hand.wave.fill"
        case .liked: "heart"
        case .shared: "arrowshape.turn.up.right"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.2), in: Circle())
            (Text(event.user.displayName).foregroundStyle(.white.opacity(0.7)) + Text(" ") + Text(event.text).foregroundStyle(.white))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .accessibilityElement(children: .combine)
    }
}

// Cœurs qui jaillissent à l'endroit touché (ADR-066).
private struct LiveTapHeartsView: View {
    let model: LiveRoomModel

    var body: some View {
        ZStack {
            ForEach(model.tapHearts) { heart in
                TapHeartView(heart: heart) { model.tapHeartFinished(heart) }
                    .position(x: heart.x, y: heart.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TapHeartView: View {
    let heart: LiveRoomModel.TapHeart
    let onFinish: () -> Void
    @State private var popped = false
    @State private var gone = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 76))
            .foregroundStyle(.red.gradient)
            .shadow(color: .black.opacity(0.25), radius: 6)
            .rotationEffect(.degrees(heart.tilt))
            .scaleEffect(gone ? 1.4 : popped ? 1 : 0.3)
            .offset(y: gone ? -90 : 0)
            .opacity(gone ? 0 : 1)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { popped = true }
                withAnimation(.easeIn(duration: 0.5).delay(0.45)) {
                    gone = true
                } completion: {
                    onFinish()
                }
            }
    }
}

// Cœurs qui montent sur la droite.
private struct FloatingHeartsView: View {
    let model: LiveRoomModel

    var body: some View {
        GeometryReader { geometry in
            ForEach(model.floatingHearts) { heart in
                FloatingHeart(heart: heart, height: geometry.size.height * 0.45) { model.heartFinished(heart) }
                    .position(x: geometry.size.width - 34, y: geometry.size.height - 110)
            }
        }
    }
}

private struct FloatingHeart: View {
    let heart: LiveRoomModel.FloatingHeart
    let height: CGFloat
    let onFinish: () -> Void
    @State private var rising = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.largeTitle)
            .foregroundStyle(.red)
            .offset(x: rising ? heart.drift : 0, y: rising ? -height : 0)
            .opacity(rising ? 0 : 1)
            .scaleEffect(rising ? 1.3 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) {
                    rising = true
                } completion: {
                    onFinish()
                }
            }
    }
}

// Pastille « EN DIRECT ».
struct LiveBadge: View {
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

// Fin du live : chiffres pour son auteur (un spectateur voit le sondage, `LiveFeedbackView`).
private struct LiveEndedView: View {
    let live: LiveStream?
    let reason: LiveEndReason?
    let isHost: Bool
    let close: () -> Void

    // Raison annoncée par la salle, sinon celle du live relu (live déjà terminé à l'ouverture).
    private var endReason: LiveEndReason { reason ?? live?.endReason ?? .host }

    var body: some View {
        VStack(spacing: 20) {
            if let live {
                AvatarView(url: live.host.avatarURL, name: live.host.displayName, size: 72)
                Text(live.host.displayName).font(.headline)
            }
            Text(isHost && endReason == .host ? "Live terminé" : endReason.message)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if isHost, let stats = live?.stats {
                Grid(horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow {
                        stat("Durée", stats.durationLabel)
                        stat("Spectateurs", "\(stats.viewersCount)")
                        stat("Pic", "\(stats.peakViewers)")
                    }
                    GridRow {
                        stat("Cœurs", "\(stats.heartsCount)")
                        stat("Cadeaux", "\(stats.giftsCount)")
                        stat("Jetons", "\(stats.giftsAmount)")
                    }
                }
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                Text("Le live n’est pas enregistré.").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Fermer", action: close)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("live.ended.close")
        }
        .padding(24)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// Contenu partagé d'un live : message et lien d'app, comme une vidéo (`VideoShareContent`).
struct LiveShareContent: Equatable {
    let content: VideoShareContent

    init(live: LiveStream) {
        content = VideoShareContent(message: "@\(live.host.username) est en direct sur TikTok Clone", link: LiveLink.url(for: live.id))
    }

    var activityItems: [Any] { content.activityItems }
}
