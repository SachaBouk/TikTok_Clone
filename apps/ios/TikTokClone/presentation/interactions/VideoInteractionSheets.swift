import SwiftUI

extension VideoPageActions {
    // Actions reliées au modèle d'interactions ; `video` est la vidéo telle que chargée (sans les changements).
    @MainActor
    init(
        interactions: VideoInteractionsModel,
        video: FeedVideo,
        togglePause: @escaping () -> Void,
        comments: @escaping () -> Void,
        share: @escaping () -> Void,
        report: @escaping () -> Void = {},
        alert: @escaping (String) -> Void,
        openHashtag: @escaping (String) -> Void = { _ in },
        gift: @escaping () -> Void = {},
        openStories: (() -> Void)? = nil
    ) {
        self.init(
            togglePause: togglePause,
            doubleTapLike: { Task { if let message = await interactions.likeFromDoubleTap(video) { alert(message) } } },
            toggle: { kind in Task { if let message = await interactions.toggle(kind, on: video) { alert(message) } } },
            comments: comments,
            share: share,
            follow: { Task { if let message = await interactions.toggleFollow(authorOf: video) { alert(message) } } },
            report: report,
            delete: { Task { if let message = await interactions.delete(video) { alert(message) } } },
            openHashtag: openHashtag,
            gift: gift,
            openStories: openStories
        )
    }
}

extension View {
    // Feuilles des commentaires, du partage et du signalement, et alerte des erreurs d'interaction, propres à l'écran
    // qui les présente (le feed, ou la vidéo seule par-dessus).
    func videoInteractionSheets(
        comments: Binding<FeedVideo?>,
        share: Binding<FeedVideo?>,
        report: Binding<FeedVideo?>,
        alert: Binding<String?>,
        interactions: VideoInteractionsModel,
        container: AppContainer
    ) -> some View {
        modifier(
            VideoInteractionSheets(
                comments: comments, share: share, report: report, alert: alert, interactions: interactions, container: container
            ))
    }
}

private struct VideoInteractionSheets: ViewModifier {
    @Binding var comments: FeedVideo?
    @Binding var share: FeedVideo?
    @Binding var report: FeedVideo?
    @Binding var alert: String?
    let interactions: VideoInteractionsModel
    let container: AppContainer
    // « Envoyer par message » choisi : la feuille des destinataires s'ouvre une fois celle du partage fermée.
    @State private var chosenForMessage: FeedVideo?
    @State private var sendByMessage: FeedVideo?

    func body(content: Content) -> some View {
        content
            .sheet(item: $comments) { video in
                CommentsView(
                    viewModel: container.makeCommentsViewModel(video: video) { delta in
                        interactions.commentsChanged(on: video, by: delta)
                    },
                    container: container
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(
                item: $share,
                onDismiss: {
                    sendByMessage = chosenForMessage
                    chosenForMessage = nil
                }
            ) { video in
                ActivityShareSheet(items: video.shareItems, allowsSendByMessage: container.session.isSignedIn) { outcome in
                    switch outcome {
                    case .shared: Task { await interactions.shareCompleted(video) }
                    // UIKit ferme parfois la feuille avant d'appeler ce gestionnaire : la feuille des
                    // destinataires s'ouvre alors tout de suite, sinon à sa fermeture.
                    case .sendByMessage:
                        if share == nil { sendByMessage = video } else { chosenForMessage = video }
                    case .cancelled: break
                    }
                    share = nil
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
            .sheet(item: $sendByMessage) { video in
                SendVideoView(viewModel: container.makeSendVideoViewModel(video: video))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            // Vidéo d'un autre compte signalée depuis le menu « … » (ADR-038).
            .reportSheet(
                Binding(
                    get: { report.map { ReportTarget.video(id: $0.id) } },
                    set: { if $0 == nil { report = nil } }
                ), container: container
            )
            .alert(
                "Action impossible",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alert ?? "")
            }
    }
}

extension View {
    // Feuille de cadeaux d'une vidéo (ADR-050), et animation à l'envoi au-dessus du lecteur, effacée après 2 s.
    func giftSheet(video: Binding<FeedVideo?>, burst: Binding<GiftBurst?>, container: AppContainer) -> some View {
        self
            .sheet(item: video) { video in
                GiftSheet(viewModel: container.makeGiftSheetViewModel(video: video), container: container) { sent in
                    burst.wrappedValue = sent
                }
                .presentationDetents([.medium, .large])
            }
            .overlay {
                if let current = burst.wrappedValue {
                    GiftBurstView(burst: current)
                        .id(current.id)
                        .task(id: current.id) {
                            try? await Task.sleep(for: .seconds(2))
                            if burst.wrappedValue == current { withAnimation { burst.wrappedValue = nil } }
                        }
                }
            }
    }
}
