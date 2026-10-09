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
// sont créés une fois, à l'apparition.
private struct LiveScreen: View {
    let route: AppRouter.LiveRoute
    let container: AppContainer
    @State private var setup: LiveRoomSetup?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let setup {
                LiveView(model: setup.model, room: setup.room, container: container)
            }
        }
        .onAppear {
            if setup == nil { setup = container.makeLiveRoom(route) }
        }
    }
}

struct LiveView: View {
    let model: LiveRoomModel
    let room: LiveKitRoom
    let container: AppContainer
    @State private var isConfirmingEnd = false
    @State private var isSharing = false
    @State private var chosenForMessage = false
    @State private var isSendingByMessage = false
    @State private var isGiving = false
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
                    if chosenForMessage { isSendingByMessage = true }
                    chosenForMessage = false
                }
            ) {
                if let live = model.live {
                    ActivityShareSheet(items: LiveShareContent(live: live).activityItems, allowsSendByMessage: container.session.isSignedIn) {
                        outcome in
                        switch outcome {
                        case .shared: container.analytics.track(.liveShared(byMessage: false))
                        // Même piège que pour une vidéo : UIKit ferme parfois la feuille avant ce gestionnaire.
                        case .sendByMessage:
                            container.analytics.track(.liveShared(byMessage: true))
                            if isSharing { chosenForMessage = true } else { isSendingByMessage = true }
                        case .cancelled: break
                        }
                        isSharing = false
                    }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $isSendingByMessage) {
                if let live = model.live {
                    SendVideoView(viewModel: container.makeSendLiveViewModel(live: live))
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
            .reportSheet($reportTarget, container: container)
            .alert(
                "Action impossible",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .connecting:
            ZStack {
                LiveVideoView(room: room).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(model.isHost ? "Lancement du live…" : "Connexion au live…").foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) { closeButton(confirm: false) }
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
            LiveEndedView(live: live, reason: reason, isHost: model.isHost) { dismiss() }
        case .live:
            liveContent
        }
    }

    private var liveContent: some View {
        ZStack {
            LiveVideoView(room: room)
                .ignoresSafeArea()
                .overlay {
                    if !model.hasVideo {
                        Text(model.isHost ? "" : "En attente de l’image…").foregroundStyle(.white.opacity(0.7))
                    }
                }
            // La vue vidéo de LiveKit garde les touchers : une couche transparente au-dessus ferme le clavier.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { isComposing = false }
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom).frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).frame(height: 320)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(spacing: 10) {
                header
                Spacer()
                gifts
                chat
                composer
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            FloatingHeartsView(model: model)
                .allowsHitTesting(false)
        }
        .confirmationDialog("Terminer le live ?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("Terminer le live", role: .destructive) { Task { await model.end() } }
        } message: {
            Text("Les spectateurs seront prévenus. Le live ne sera pas enregistré.")
        }
    }

    // ─── En-tête : auteur, titre, « EN DIRECT », spectateurs, fermer ───

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if let live = model.live {
                AvatarView(url: live.host.avatarURL, name: live.host.displayName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.host.displayName).font(.subheadline.bold()).lineLimit(1)
                    if let title = live.title {
                        Text(title).font(.caption).lineLimit(2).opacity(0.85)
                    }
                    HStack(spacing: 8) {
                        LiveBadge()
                        Label("\(model.viewersCount)", systemImage: "eye").font(.caption.bold())
                            .accessibilityLabel("\(model.viewersCount) spectateurs")
                        Label("\(model.heartsTotal)", systemImage: "heart.fill").font(.caption.bold())
                            .accessibilityLabel("\(model.heartsTotal) cœurs")
                    }
                }
                .foregroundStyle(.white)
                .shadow(radius: 2)
            }
            Spacer()
            if model.isHost {
                Button("Changer de caméra", systemImage: "arrow.triangle.2.circlepath.camera") { Task { await model.switchCamera() } }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            closeButton(confirm: model.isHost)
        }
    }

    private func closeButton(confirm: Bool) -> some View {
        Button(confirm ? "Terminer le live" : "Fermer", systemImage: "xmark") {
            if confirm { isConfirmingEnd = true } else { dismiss() }
        }
        .labelStyle(.iconOnly)
        .font(.title3.bold())
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
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
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.messages) { message in
                        LiveChatRow(message: message, isHost: message.user.id == model.live?.host.id)
                            .contextMenu {
                                Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                                if model.canDelete(message) {
                                    Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await model.delete(message) } }
                                }
                            }
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 220)
            .defaultScrollAnchor(.bottom)
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
            .onChange(of: model.messages.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    // ─── Saisie et actions ───

    private var composer: some View {
        HStack(spacing: 10) {
            if container.session.isSignedIn {
                TextField("Ajouter un commentaire…", text: Binding(get: { model.draft }, set: { model.draft = $0 }))
                    .focused($isComposing)
                    .submitLabel(.send)
                    .onSubmit { Task { await model.send() } }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("live.message")
                if isComposing || !model.draft.isEmpty {
                    Button("Envoyer", systemImage: "arrow.up.circle.fill") { Task { await model.send() } }
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .disabled(!model.canSend)
                }
            } else {
                Button("Connecte-toi pour écrire") { container.session.requestSignIn() }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
            }
            if !isComposing {
                actionButton("Partager", systemImage: "arrowshape.turn.up.right.fill") { isSharing = true }
                if !model.isHost {
                    actionButton("Cadeau", systemImage: "gift.fill") {
                        if container.session.isSignedIn { isGiving = true } else { container.session.requestSignIn() }
                    }
                    Menu {
                        Button("Signaler", systemImage: "flag") {
                            guard let live = model.live else { return }
                            if container.session.isSignedIn { reportTarget = .live(id: live.id) } else { container.session.requestSignIn() }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.title3).foregroundStyle(.white).frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Plus d’options")
                    actionButton("Cœur", systemImage: "heart.fill", tint: .pink) { model.tapHeart() }
                        .accessibilityIdentifier("live.heart")
                }
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(tint)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
    }
}

// Message du chat : pseudo en gras, puis le texte. L'auteur du live est marqué.
private struct LiveChatRow: View {
    let message: LiveChatMessage
    let isHost: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: message.user.avatarURL, name: message.user.displayName, size: 24)
            (Text(message.user.username).bold().foregroundStyle(.white.opacity(0.75))
                + Text(isHost ? " · Créateur" : "").font(.caption2.bold()).foregroundStyle(.pink)
                + Text("  ") + Text(message.content).foregroundStyle(.white))
                .font(.subheadline)
                .shadow(radius: 1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}

// Cœurs qui montent sur la droite.
private struct FloatingHeartsView: View {
    let model: LiveRoomModel

    var body: some View {
        GeometryReader { geometry in
            ForEach(model.floatingHearts) { heart in
                FloatingHeart(heart: heart, height: geometry.size.height * 0.45) { model.heartFinished(heart) }
                    .position(x: geometry.size.width - 34, y: geometry.size.height - 90)
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
            .font(.title)
            .foregroundStyle(.pink)
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

// Fin du live : chiffres pour son auteur, raison pour un spectateur.
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
