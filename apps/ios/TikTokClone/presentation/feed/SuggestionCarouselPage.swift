import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// Page « comptes suggérés » du feed « Pour toi » (choix du développeur, comme TikTok ; `SuggestionCarouselRules`) :
// cartes à faire défiler horizontalement (photo, nom, raison, ⓘ et ×), les voisines dépassent sur les côtés ;
// « Pas intéressé(e) » et « Suivre » sous la carte du milieu. Le fond prend la couleur de la photo de la carte affichée
// (`SuggestionTone`) et change à chaque carte. Suggestions de l'ADR-058 (`SuggestionsModel`), écartées sur l'appareil.
struct SuggestionCarouselPage: View {
    let container: AppContainer
    // Page affichée : la mesure d'audience compte l'affichage.
    let isCurrent: Bool
    let openProfile: (String) -> Void
    @State private var selectedID: String?
    @State private var tones: [String: SuggestionTone] = [:]
    @State private var isShowingInfo = false
    @State private var followError: String?
    @State private var advanceTask: Task<Void, Never>?

    private var model: SuggestionsModel { container.suggestions }
    private var interactions: VideoInteractionsModel { container.videoInteractions }

    // Mesures relevées sur les captures de TikTok (écran de 874 pt de haut, carte à 82 % de la largeur).
    private static let cardTop = 0.225
    private static let cardHeight = 0.4625
    private static let buttonsTop = 0.7065
    private static let hintCenter = 0.875
    private static let cardSpacing: CGFloat = 16

    var body: some View {
        let suggestions = model.visible(blocked: interactions.blockedUserIDs)
        let current = suggestions.first { $0.id == selectedID } ?? suggestions.first
        GeometryReader { geometry in
            let size = geometry.size
            let cardWidth = (size.width * 0.826).rounded()
            let margin = (size.width - cardWidth) / 2
            ZStack(alignment: .top) {
                background(for: current, height: size.height)
                cards(suggestions, width: cardWidth, height: (size.height * Self.cardHeight).rounded(), margin: margin)
                    .padding(.top, size.height * Self.cardTop)
                if let current {
                    buttons(for: current)
                        .frame(width: cardWidth)
                        .padding(.top, size.height * Self.buttonsTop)
                }
                swipeHint
                    .position(x: size.width / 2, y: size.height * Self.hintCenter)
            }
        }
        .onChange(of: isCurrent, initial: true) { _, isCurrent in
            if isCurrent { container.analytics.track(.suggestionCarouselShown(count: suggestions.count)) }
        }
        .onDisappear { advanceTask?.cancel() }
        .sheet(isPresented: $isShowingInfo) { SuggestionInfoSheet() }
        .alert("Abonnements", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
        .accessibilityIdentifier("suggestions.carousel")
    }

    // Couleur de la carte affichée en haut, fondue dans le noir vers le bas ; elle change en douceur d'une carte à l'autre.
    private func background(for suggestion: AccountSuggestion?, height: CGFloat) -> some View {
        let tone = suggestion.map { tones[$0.id] ?? SuggestionTone.fallback(for: $0.user.username) }
        let color = tone.map { Color(hue: $0.hue, saturation: $0.saturation, brightness: $0.brightness) } ?? Color(white: 0.3)
        return LinearGradient(
            stops: [.init(color: color, location: 0), .init(color: color.opacity(0.55), location: 0.4), .init(color: .black, location: 0.75)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
        .animation(.easeInOut(duration: 0.4), value: tone)
    }

    private func cards(_ suggestions: [AccountSuggestion], width: CGFloat, height: CGFloat, margin: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.cardSpacing) {
                ForEach(suggestions) { suggestion in
                    SuggestionCard(
                        suggestion: suggestion,
                        open: { openProfile(suggestion.user.username) },
                        info: { isShowingInfo = true },
                        dismiss: { dismiss(suggestion, among: suggestions) }
                    )
                    .frame(width: width, height: height)
                    .task(id: suggestion.user.avatarURL) { await loadTone(of: suggestion) }
                    .id(suggestion.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID)
        .scrollIndicators(.hidden)
        .frame(height: height)
    }

    private func buttons(for suggestion: AccountSuggestion) -> some View {
        let following = interactions.isFollowing(suggestion.user.id, loaded: false)
        return HStack(spacing: 11) {
            Button {
                dismiss(suggestion, among: model.visible(blocked: interactions.blockedUserIDs))
            } label: {
                Text("Pas intéressé(e)").frame(maxWidth: .infinity, minHeight: 47)
                    .background(Color(white: 0.24), in: Capsule())
            }
            .accessibilityIdentifier("suggestions.notInterested")
            Button {
                toggleFollow(suggestion, following: following)
            } label: {
                Text(FollowStatus(following: following, followedBy: suggestion.followsYou).title)
                    .frame(maxWidth: .infinity, minHeight: 47)
                    .background(following ? Color(white: 0.24) : Color.brandPink, in: Capsule())
            }
            .accessibilityIdentifier("suggestions.follow")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: following)
    }

    // « ⌃⌃ » : balayer vers le haut pour reprendre les vidéos.
    private var swipeHint: some View {
        VStack(spacing: -7) {
            Image(systemName: "chevron.up")
            Image(systemName: "chevron.up")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white.opacity(0.55))
        .accessibilityHidden(true)
    }

    // × ou « Pas intéressé(e) » : la carte part (écartée sur l'appareil), la voisine prend sa place.
    private func dismiss(_ suggestion: AccountSuggestion, among suggestions: [AccountSuggestion]) {
        let neighbor = SuggestionCarouselRules.neighbor(of: suggestion.id, in: suggestions.map(\.id))
        container.analytics.track(.suggestionDismissed(userID: suggestion.id))
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedID = neighbor
            model.dismiss(suggestion)
        }
    }

    // « Suivre » : « Abonné(e) », puis la carte suivante après un instant. « Abonné(e) » touché : désabonnement.
    private func toggleFollow(_ suggestion: AccountSuggestion, following: Bool) {
        advanceTask?.cancel()
        Task {
            if case .failed(let message) = await interactions.setFollowing(suggestion.user, active: !following, wasFollowing: following) {
                followError = message
            }
        }
        guard !following else { return }
        let ids = model.visible(blocked: interactions.blockedUserIDs).map(\.id)
        guard let next = SuggestionCarouselRules.next(after: suggestion.id, in: ids) else { return }
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, selectedID ?? ids.first == suggestion.id else { return }
            withAnimation(.easeInOut(duration: 0.35)) { selectedID = next }
        }
    }

    private func loadTone(of suggestion: AccountSuggestion) async {
        guard tones[suggestion.id] == nil, let url = suggestion.user.avatarURL, let image = await ThumbnailCache.shared.load(url) else { return }
        if let tone = await AverageColor.tone(of: image) { tones[suggestion.id] = tone }
    }
}

// Une carte : ⓘ et × en haut, grande photo ronde, nom, raison (photos des comptes suivis qui le suivent).
private struct SuggestionCard: View {
    let suggestion: AccountSuggestion
    let open: () -> Void
    let info: () -> Void
    let dismiss: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.black.opacity(0.42))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .top) {
                Button(action: open) {
                    VStack(spacing: 0) {
                        AvatarView(url: suggestion.user.avatarURL, name: suggestion.user.displayName, size: 153)
                            .padding(.top, 81)
                        Text(suggestion.user.displayName)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.top, 22)
                            .padding(.horizontal, 20)
                        reason.padding(.top, 14).padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suggestions.card")
            }
            .overlay(alignment: .topLeading) {
                Button("Pourquoi ces comptes ?", systemImage: "info.circle", action: info)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17))
                    .frame(width: 44, height: 44)
                    .padding(6)
                    .accessibilityIdentifier("suggestions.info")
            }
            .overlay(alignment: .topTrailing) {
                Button("Écarter @\(suggestion.user.username)", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .padding(8)
                    .accessibilityIdentifier("suggestions.dismiss")
            }
            .foregroundStyle(.white.opacity(0.9))
    }

    private var reason: some View {
        HStack(spacing: 10) {
            if !suggestion.followsYou, !suggestion.followedBy.isEmpty {
                HStack(spacing: -8) {
                    ForEach(suggestion.followedBy, id: \.id) { user in
                        AvatarView(url: user.avatarURL, name: user.displayName, size: 25)
                            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            Text(suggestion.carouselReason)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(suggestion.followedBy.isEmpty || suggestion.followsYou ? .center : .leading)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(suggestion.carouselReason)
    }
}

// ⓘ : pourquoi ces comptes.
private struct SuggestionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pourquoi ces comptes ?").font(.title3.bold())
            Label("Des comptes suivis par les personnes que tu suis.", systemImage: "person.2")
            Label("Des personnes qui te suivent et que tu ne suis pas encore.", systemImage: "person.badge.plus")
            Label("« Pas intéressé(e) » ou × écarte un compte ; ce choix reste sur cet iPhone.", systemImage: "hand.raised")
            Button {
                dismiss()
            } label: {
                Text("OK").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.brandPink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .font(.subheadline)
        .padding(24)
        .presentationDetents([.height(320)])
        // Fond plein : la page colorée et le bouton « Suivre » transparaissaient sous le verre d'iOS 26.
        .presentationBackground(Color(white: 0.13))
        .presentationDragIndicator(.visible)
    }
}

// Couleur moyenne d'une photo (Core Image, hors du fil principal), ravivée pour le fond (`SuggestionTone`).
// Piège rencontré : un contexte sans espace de travail (`workingColorSpace` nul) rendait un pixel vide ; contexte par
// défaut, lu en sRGB.
private enum AverageColor {
    private static let context = CIContext()

    static func tone(of image: UIImage) async -> SuggestionTone? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .utility) {
            let input = CIImage(cgImage: cgImage)
            let filter = CIFilter.areaAverage()
            filter.inputImage = input
            filter.extent = input.extent
            guard let output = filter.outputImage, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: output.extent, format: .RGBA8, colorSpace: sRGB)
            guard pixel[3] > 0 else { return nil }
            return SuggestionTone(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
        }.value
    }
}
