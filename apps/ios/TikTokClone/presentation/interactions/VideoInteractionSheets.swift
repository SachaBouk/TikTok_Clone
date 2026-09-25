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
        alert: @escaping (String) -> Void
    ) {
        self.init(
            togglePause: togglePause,
            doubleTapLike: { Task { if let message = await interactions.likeFromDoubleTap(video) { alert(message) } } },
            toggle: { kind in Task { if let message = await interactions.toggle(kind, on: video) { alert(message) } } },
            comments: comments,
            share: share,
            follow: { Task { if let message = await interactions.toggleFollow(authorOf: video) { alert(message) } } }
        )
    }
}

extension View {
    // Feuilles des commentaires et du partage, et alerte des erreurs d'interaction, propres à l'écran qui les
    // présente (le feed, ou la vidéo seule par-dessus).
    func videoInteractionSheets(
        comments: Binding<FeedVideo?>,
        share: Binding<FeedVideo?>,
        alert: Binding<String?>,
        interactions: VideoInteractionsModel,
        container: AppContainer
    ) -> some View {
        self
            .sheet(item: comments) { video in
                CommentsView(
                    viewModel: container.makeCommentsViewModel(video: video) { delta in
                        interactions.commentsChanged(on: video, by: delta)
                    },
                    container: container
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: share) { video in
                ActivityShareSheet(items: video.shareItems) { completed in
                    if completed { Task { await interactions.shareCompleted(video) } }
                    share.wrappedValue = nil
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
            .alert("Action impossible", isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: { if !$0 { alert.wrappedValue = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alert.wrappedValue ?? "")
            }
    }
}
