import SwiftUI

// Lives à faire défiler (ADR-066), ouverts par l'icône « LIVE » de l'accueil : une page par live, balayer vers le haut
// pour le suivant. Seul le live affiché est connecté (salle créée à l'arrivée sur sa page, quittée en la quittant) ; les
// autres pages montrent la photo floutée de leur auteur.
struct LiveFeedScreen: View {
    let container: AppContainer
    @State private var model: LiveFeedModel?
    // Salle du live affiché.
    @State private var current: (id: String, setup: LiveRoomSetup)?
    // Saisie d'un commentaire sur le live affiché, au-dessus du clavier.
    @State private var isComposing = false
    @FocusState private var composerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                switch model.state {
                case .loading:
                    LiveLoadingView(host: nil).overlay(alignment: .topTrailing) { closeButton }
                case .empty:
                    unavailable(
                        "Aucun live en ce moment", detail: "Reviens plus tard pour regarder des lives.", systemImage: "dot.radiowaves.left.and.right")
                case .failed(let message):
                    unavailable("Lives indisponibles", detail: message, systemImage: "wifi.exclamationmark")
                case .loaded:
                    pages(model)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isComposing, let current {
                LiveComposer(model: current.setup.model, isFocused: $composerFocused)
            }
        }
        .onChange(of: composerFocused) { _, focused in
            if !focused { isComposing = false }
        }
        .onChange(of: isComposing) { _, composing in
            if !composing { composerFocused = false }
        }
        .task {
            guard model == nil else { return }
            let feed = container.makeLiveFeedModel()
            model = feed
            await feed.start()
        }
    }

    // Pages en plein écran : la `ScrollView` ignore la zone de sécurité et le clavier (les pages gardent leur taille) ;
    // chaque page remet les marges du haut et du bas à ses boutons (`insets`) ; la saisie passe au-dessus du clavier.
    private func pages(_ model: LiveFeedModel) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.lives) { live in
                        page(live, model: model, insets: geometry.safeAreaInsets)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(live.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { model.currentID }, set: { model.currentID = $0 }))
            .scrollIndicators(.hidden)
            .hidesScrollEdgeEffects()
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: model.currentID, initial: true) { _, id in connect(to: id, in: model) }
    }

    @ViewBuilder
    private func page(_ live: LiveStream, model: LiveFeedModel, insets: EdgeInsets) -> some View {
        if let current, current.id == live.id {
            LiveView(
                model: current.setup.model, room: current.setup.room, container: container, hasNextLive: model.hasNext(after: live.id),
                isInFeed: true,
                insets: insets, feedComposer: $isComposing
            )
            .id(live.id)
        } else {
            LiveLoadingView(host: live.host)
        }
    }

    // Arrivée sur une page : sa salle est créée ; la précédente disparaît de l'écran, et `LiveView` la quitte.
    private func connect(to id: String?, in model: LiveFeedModel) {
        guard let id, current?.id != id, let live = model.lives.first(where: { $0.id == id }) else { return }
        isComposing = false
        current = (id, container.makeLiveRoom(mode: .viewer(liveID: id, source: .discover), preview: live))
    }

    private var closeButton: some View {
        Button("Fermer", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .padding(.horizontal, 12)
            .accessibilityIdentifier("liveFeed.close")
    }

    private func unavailable(_ title: String, detail: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        } actions: {
            Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent).tint(.brandPink)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// Fin d'un live, pour un spectateur (ADR-066) : « Comment s'est passé ce live ? », puis le live suivant (balayer vers le
// haut) dans les lives à faire défiler, sinon « Fermer ». La réponse ne va qu'à la mesure d'audience.
struct LiveFeedbackView: View {
    let model: LiveRoomModel
    let live: LiveStream?
    let reason: LiveEndReason?
    let hasNextLive: Bool
    let isInFeed: Bool
    var insets = EdgeInsets()
    let close: () -> Void

    var body: some View {
        @Bindable var model = model
        ZStack {
            background
            VStack(spacing: 18) {
                Spacer().frame(height: 40)
                if let host = live?.host {
                    // Faute d'image du live : la photo de l'auteur remplit la vignette (rond plus grand que le cadre).
                    AvatarView(url: host.avatarURL, name: host.displayName, size: 200)
                        .frame(width: 96, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                Text("Comment s’est passé ce live ?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text((reason ?? live?.endReason ?? .host).message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                if model.feedbackSent {
                    Label("Merci pour ton avis", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .padding(.top, 24)
                        .transition(.opacity)
                        .accessibilityIdentifier("live.feedback.thanks")
                } else {
                    VStack(spacing: 12) {
                        ForEach(LiveFeedback.allCases, id: \.self) { answer in
                            Button {
                                model.feedback = answer
                            } label: {
                                Text(answer.label)
                                    .font(.body.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: model.feedback == answer ? 1.5 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.feedback == answer ? .isSelected : [])
                        }
                        Button {
                            withAnimation { model.submitFeedback() }
                        } label: {
                            Text("Envoyer")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    model.feedback == nil ? Color.white.opacity(0.08) : Color.brandPink, in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(model.feedback == nil ? .white.opacity(0.4) : .white)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.feedback == nil)
                        .padding(.top, 14)
                        .accessibilityIdentifier("live.feedback.send")
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 8)
                }
                Spacer()
                if isInFeed && hasNextLive {
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.compact.up").font(.title)
                        Text("Balaie vers le haut pour le live suivant").font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 24)
                } else if !isInFeed {
                    Button("Fermer", action: close)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.2))
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("live.ended.close")
                }
            }
            .foregroundStyle(.white)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .overlay(alignment: .topTrailing) {
            if isInFeed {
                Button("Fermer", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .padding(.horizontal, 12)
                    .padding(.top, insets.top)
                    .accessibilityIdentifier("live.ended.close")
            }
        }
    }

    // Dégradé sombre, rose à gauche et bleu à droite, comme TikTok.
    private var background: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.08)
            RadialGradient(
                colors: [Color(red: 0.75, green: 0.05, blue: 0.25).opacity(0.75), .clear], center: .leading, startRadius: 10, endRadius: 360)
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.45, blue: 0.7).opacity(0.7), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

// Fiche de l'auteur d'un live (ADR-066), ouverte en touchant sa pastille : photo, nom, pseudo, abonnés, abonnements,
// bio, « Suivre » et le drapeau « Signaler ».
struct LiveHostSheet: View {
    @State var model: LiveHostModel
    let host: UserSummary
    let container: AppContainer
    let onReport: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var follows: Bool { container.videoInteractions.isFollowing(host.id, loaded: model.follows) }
    private var isOwn: Bool { container.session.profile?.id == host.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                AvatarView(url: host.avatarURL, name: host.displayName, size: 82)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.displayName).font(.system(size: 30, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(host.username).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !isOwn {
                    Button("Signaler", systemImage: "flag") {
                        dismiss()
                        // La feuille de signalement s'ouvre une fois celle-ci fermée.
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            onReport()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6), in: Circle())
                    .accessibilityIdentifier("liveHost.report")
                }
            }
            if let profile = model.profile {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count(profile.followersCount, "abonné")) · \(count(profile.followingCount, "abonnement"))")
                        .font(.title3.weight(.medium))
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio).font(.body).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            } else if model.failed {
                Text("Profil indisponible").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            if !isOwn {
                Button {
                    Task { _ = await container.videoInteractions.setFollowing(host, active: !follows, wasFollowing: follows) }
                } label: {
                    Label(follows ? "Abonné(e)" : "Suivre", systemImage: follows ? "checkmark" : "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(follows ? Color(.systemGray5) : Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(follows ? Color.primary : Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("liveHost.follow")
            }
        }
        .padding(20)
        .padding(.top, 8)
        .environment(\.colorScheme, .light)
        .task { await model.load() }
    }

    private func count(_ value: Int, _ word: String) -> String {
        // Nombre entier, comme TikTok (« 9050 abonnés »).
        "\(value) \(word)\(value > 1 ? "s" : "")"
    }
}

extension View {
    // iOS 26 floute le contenu qui passe sous la barre d'état d'une `ScrollView` : sans objet pour des pages vidéo.
    @ViewBuilder
    func hidesScrollEdgeEffects() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true)
        } else {
            self
        }
    }
}
