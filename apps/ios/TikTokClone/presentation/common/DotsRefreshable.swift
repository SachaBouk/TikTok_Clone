import SwiftUI

// Tirer pour actualiser, comme TikTok (choix du développeur, d'après une vidéo de TikTok) : à la place de la roue du
// système, les deux points rose et cyan (`DotsLoader`) apparaissent dans l'espace libéré en haut et tournent l'un
// autour de l'autre à mesure que l'on tire ; relâchés au-delà du seuil, le contenu reste un peu descendu et les points
// s'échangent sur place pendant l'actualisation, puis tout remonte. Pour une `ScrollView` ou une `List` (iOS 18 :
// géométrie et phase du défilement).
extension View {
    func dotsRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(DotsRefreshModifier(action: action))
    }
}

// Règles du geste, sans SwiftUI (testées).
enum PullToRefresh {
    // Distance à tirer pour déclencher l'actualisation.
    static let threshold: CGFloat = 70
    // Hauteur gardée en haut pendant l'actualisation (les points au milieu).
    static let refreshingHeight: CGFloat = 56
    // Les points restent au moins ce temps : une actualisation rapide ne fait pas qu'un éclair.
    static let minimumDuration: Duration = .milliseconds(600)

    // Apparition des points, de 0 à 1, selon la distance tirée.
    static func progress(pull: CGFloat) -> CGFloat {
        min(max(pull / threshold, 0), 1)
    }

    // Relâché assez bas, et pas déjà en cours.
    static func shouldRefresh(pull: CGFloat, isRefreshing: Bool) -> Bool {
        !isRefreshing && pull >= threshold
    }

    // Centre vertical des points : au milieu de l'espace libéré (ou de la hauteur gardée pendant l'actualisation).
    static func indicatorCenter(pull: CGFloat, isRefreshing: Bool) -> CGFloat {
        isRefreshing ? max(refreshingHeight, pull) / 2 : pull / 2
    }

    // Pendant le geste, les points tournent avec la distance tirée (un échange complet par seuil).
    static func phase(pull: CGFloat) -> Double {
        Double(max(pull, 0) / threshold)
    }
}

private struct DotsRefreshModifier: ViewModifier {
    let action: @MainActor () async -> Void
    @State private var pull: CGFloat = 0
    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            // Contenu gardé descendu pendant l'actualisation.
            .contentMargins(.top, isRefreshing ? PullToRefresh.refreshingHeight : 0, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Distance tirée au-delà du haut (0 au repos), marge de l'actualisation comprise.
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top)) + (isRefreshing ? PullToRefresh.refreshingHeight : 0)
            } action: { _, new in
                pull = new
            }
            .onScrollPhaseChange { old, new in
                guard old == .interacting, new != .interacting, PullToRefresh.shouldRefresh(pull: pull, isRefreshing: isRefreshing) else {
                    return
                }
                Task { await refresh() }
            }
            .overlay(alignment: .top) { indicator }
    }

    @ViewBuilder
    private var indicator: some View {
        let progress = isRefreshing ? 1 : PullToRefresh.progress(pull: pull)
        if progress > 0 {
            DotsLoader(size: 10, phase: isRefreshing ? nil : PullToRefresh.phase(pull: pull))
                .scaleEffect(0.6 + 0.4 * progress)
                .opacity(progress)
                .frame(height: 10)
                .offset(y: PullToRefresh.indicatorCenter(pull: pull, isRefreshing: isRefreshing) - 5)
                .allowsHitTesting(false)
                .accessibilityIdentifier("refresh.dots")
        }
    }

    private func refresh() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isRefreshing = true }
        async let minimum: Void = { try? await Task.sleep(for: PullToRefresh.minimumDuration) }()
        await action()
        await minimum
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isRefreshing = false }
    }
}
