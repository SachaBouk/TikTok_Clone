import SwiftUI
import UIKit

// Bandeau de notification dans l'app (ADR-078), comme une notification d'iOS : en haut, arrondi, sur fond de verre ;
// photo (ou icône), titre, texte sur deux lignes, miniature de la vidéo. Toucher : l'écran concerné ; balayer vers le
// haut : fermé ; doigt posé : il reste.
struct InAppBannerView: View {
    let banner: InAppBanner
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let onHold: (Bool) -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(banner.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumbnail = banner.thumbnailURL {
                CachedThumbnail(url: thumbnail)
                    .frame(width: 36, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 10)
        .offset(y: min(offset, 0) + max(offset, 0) * 0.2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    onHold(true)
                    offset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height < -24 || value.predictedEndTranslation.height < -80 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                        onHold(false)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.spokenText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Ouvre la notification.")
        .accessibilityAction(named: "Fermer", onDismiss)
        .accessibilityIdentifier("inAppBanner")
    }

    @ViewBuilder
    private var leading: some View {
        if banner.avatarURL != nil || banner.symbol == nil {
            AvatarView(url: banner.avatarURL, name: banner.title, size: 40)
        } else if let symbol = banner.symbol {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.brandPink.gradient, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

// Couche des bandeaux, dans sa propre fenêtre (`InAppBannerWindow`) : par-dessus les plein écrans et les feuilles.
struct InAppBannerOverlay: View {
    let container: AppContainer
    // Cadre du bandeau dans la fenêtre : seuls les touchers dedans lui reviennent.
    let onFrameChange: (CGRect) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: InAppBannerModel { container.banners }

    var body: some View {
        VStack {
            if let banner = model.current {
                InAppBannerView(banner: banner) {
                    if let target = model.open() { container.router.open(target, me: container.session.profile?.summary) }
                } onDismiss: {
                    model.dismiss()
                } onHold: { held in
                    model.setHeld(held)
                }
                .id(banner.key)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    onFrameChange($0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15), value: model.current?.key)
        .onChange(of: model.current == nil, initial: true) { _, empty in
            if empty { onFrameChange(.zero) }
        }
    }
}

// Vibration légère et annonce VoiceOver à l'arrivée d'un bandeau (pas de son).
@MainActor
enum InAppBannerFeedback {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func play(for banner: InAppBanner) {
        generator.impactOccurred()
        Accessibility.announce(banner.spokenText)
    }
}

// Fenêtre transparente posée au-dessus de la fenêtre de l'app : les plein écrans (vidéo seule, stories) et les
// feuilles sont présentés dans la fenêtre de l'app, un bandeau posé dans celle-ci passerait dessous. Seuls les
// touchers sur le bandeau lui reviennent (`interactiveFrame`), les autres traversent. Cachée sans bandeau : elle ne
// touche ni à la barre d'état ni à l'orientation.
final class InAppBannerWindow: UIWindow {
    var interactiveFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

// Installe la fenêtre des bandeaux dans la scène de l'app (posé une fois par RootView).
struct InAppBannerWindowInstaller: UIViewRepresentable {
    let container: AppContainer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.onWindow = { [weak coordinator = context.coordinator] scene in coordinator?.install(in: scene, container: container) }
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        var onWindow: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { onWindow?(scene) }
        }
    }

    @MainActor
    final class Coordinator {
        private var window: InAppBannerWindow?

        func install(in scene: UIWindowScene, container: AppContainer) {
            guard window == nil else { return }
            let window = InAppBannerWindow(windowScene: scene)
            window.windowLevel = .normal + 1
            window.backgroundColor = .clear
            let host = UIHostingController(
                rootView: InAppBannerOverlay(container: container) { [weak window] frame in
                    window?.interactiveFrame = frame
                }
                .environment(container.session)
            )
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = true
            self.window = window
            follow(container.banners)
        }

        // Montrée dès qu'un bandeau arrive, cachée une fois l'animation de sortie finie. Suivi sur le modèle, pas dans la
        // vue : une fenêtre cachée ne met pas sa vue SwiftUI à jour (bug rencontré : la fenêtre ne se montrait jamais).
        private func follow(_ banners: InAppBannerModel) {
            withObservationTracking {
                _ = banners.current
            } onChange: {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.update(banners)
                    self.follow(banners)
                }
            }
        }

        private func update(_ banners: InAppBannerModel) {
            if banners.current != nil {
                window?.isHidden = false
            } else {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    if banners.current == nil { self?.window?.isHidden = true }
                }
            }
        }
    }
}
