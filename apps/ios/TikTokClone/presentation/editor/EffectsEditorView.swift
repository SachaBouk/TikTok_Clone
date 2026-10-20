import SwiftUI

// Séance de l'éditeur d'effets (ADR-063) : plages posées, choisie, annuler / rétablir propres à la séance. « Enregistrer »
// les donne au plan en un seul pas d'annulation ; « Annuler » les oublie.
@MainActor
@Observable
final class EffectsSession {
    private(set) var track: EffectTrack
    private(set) var history = EditHistory<EffectTrack>()
    var selectedID: UUID?
    private let initial: [TimedEffect]
    // Piste au début d'un geste (bord d'une plage) : un seul pas d'annulation pour tout le geste.
    private var interactionBase: EffectTrack?

    init(effects: [TimedEffect], duration: Duration) {
        let track = EffectTrack(effects: effects, duration: duration)
        self.track = track
        initial = track.effects
    }

    var effects: [TimedEffect] { track.effects }
    var hasChanges: Bool { track.effects != initial }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var selected: TimedEffect? { selectedID.flatMap { id in track.effects.first { $0.id == id } } }

    // Effet posé à la tête de lecture, pour 2 s ; il devient la plage choisie. Faux s'il ne peut pas l'être.
    @discardableResult
    func add(_ effect: VideoEffect, at time: Duration) -> Bool {
        let before = track
        guard let added = track.add(effect, at: time) else { return false }
        history.record(before, current: track)
        selectedID = added.id
        return true
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        let before = track
        track.remove(id)
        history.record(before, current: track)
        selectedID = nil
    }

    func setStart(_ start: Duration) {
        guard let id = selectedID else { return }
        if interactionBase == nil { interactionBase = track }
        track.setStart(start, of: id)
    }

    func setEnd(_ end: Duration) {
        guard let id = selectedID else { return }
        if interactionBase == nil { interactionBase = track }
        track.setEnd(end, of: id)
    }

    func endInteraction() {
        guard let base = interactionBase else { return }
        interactionBase = nil
        history.record(base, current: track)
    }

    func undo() {
        guard let previous = history.undo(track) else { return }
        track = previous
        dropMissingSelection()
    }

    func redo() {
        guard let next = history.redo(track) else { return }
        track = next
        dropMissingSelection()
    }

    private func dropMissingSelection() {
        if let id = selectedID, !track.effects.contains(where: { $0.id == id }) { selectedID = nil }
    }
}

// Éditeur d'effets plein écran, comme TikTok (version réduite, ADR-063) : « Annuler » et « Enregistrer », la vidéo (toucher
// = lecture ou pause), supprimer / rétablir / annuler à droite, frise de toute la vidéo avec la tête de lecture et les
// plages en couleur (toucher une plage la choisit, ses bords se déplacent, glisser ailleurs déplace la lecture), onglets
// des catégories et grille des effets : un toucher pose l'effet à la tête de lecture, pour 2 s.
struct EffectsEditorView: View {
    let model: VideoEditorViewModel
    let preview: EditorPreviewPlayer
    let thumbnails: LookThumbnailStore
    @State private var session: EffectsSession
    @State private var category: VideoEffect.Category = .visual
    @State private var limitReached = false
    @Environment(\.dismiss) private var dismiss

    init(model: VideoEditorViewModel, preview: EditorPreviewPlayer, thumbnails: LookThumbnailStore) {
        self.model = model
        self.preview = preview
        self.thumbnails = thumbnails
        _session = State(initialValue: EffectsSession(effects: model.plan.effects, duration: model.plan.outputDuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                PlayerLayerView(player: preview.player, fills: !preview.isSimplified)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .background(Color.black)
                    .overlay(alignment: .bottom) {
                        if preview.isSimplified {
                            Text("Aperçu simplifié")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.5), in: Capsule())
                                .padding(6)
                        }
                    }
                    .onTapGesture { preview.togglePlayback() }
                    .accessibilityIdentifier("effects.preview")
                Spacer(minLength: 0)
                    .overlay(alignment: .trailing) { sideActions.padding(.trailing, 16) }
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 8)
            Capsule().fill(.white.opacity(0.3)).frame(width: 36, height: 4).padding(.bottom, 14)
            EffectTimeline(session: session, preview: preview, duration: model.plan.outputDuration)
                .frame(height: 44)
                .padding(.horizontal, 16)
            categories
                .padding(.top, 22)
            Divider().overlay(.white.opacity(0.15))
            grid
                .frame(height: 230)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .alert("\(EffectTrack.maxEffects) effets au plus.", isPresented: $limitReached) {
            Button("OK", role: .cancel) {}
        }
        .task { await thumbnails.load(from: model) }
    }

    private var topBar: some View {
        HStack {
            Button("Annuler") {
                preview.pause()
                dismiss()
            }
            .accessibilityIdentifier("effects.cancel")
            Spacer()
            Button("Enregistrer") {
                if session.hasChanges { model.setEffects(session.effects) }
                dismiss()
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("effects.save")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    // Supprimer la plage choisie, rétablir, annuler.
    private var sideActions: some View {
        VStack(spacing: 0) {
            sideButton("Supprimer l'effet", systemImage: "trash", identifier: "effects.delete", enabled: session.selected != nil) {
                session.removeSelected()
            }
            Divider().overlay(.white.opacity(0.15)).padding(.horizontal, 10)
            sideButton("Rétablir", systemImage: "arrow.uturn.forward", identifier: "effects.redo", enabled: session.canRedo) {
                session.redo()
            }
            Divider().overlay(.white.opacity(0.15)).padding(.horizontal, 10)
            sideButton("Annuler", systemImage: "arrow.uturn.backward", identifier: "effects.undo", enabled: session.canUndo) {
                session.undo()
            }
        }
        .frame(width: 52)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sideButton(_ title: String, systemImage: String, identifier: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
        }
        .foregroundStyle(enabled ? Color.white : .white.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var categories: some View {
        HStack(spacing: 28) {
            ForEach(VideoEffect.Category.allCases) { option in
                Button {
                    category = option
                } label: {
                    VStack(spacing: 8) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(category == option ? Color.white : .white.opacity(0.55))
                        Capsule().fill(category == option ? Color.white : .clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .accessibilityAddTraits(category == option ? .isSelected : [])
                .accessibilityIdentifier("effects.category.\(option.rawValue)")
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 16) {
                ForEach(category.effects) { effect in
                    Button {
                        if !session.add(effect, at: preview.currentTime) { limitReached = true }
                    } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let image = thumbnails.effects[effect] {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.12)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(effect.title)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityLabel(effect.title)
                    .accessibilityHint("Pose l'effet à la tête de lecture")
                    .accessibilityIdentifier("effects.effect.\(effect.rawValue)")
                }
            }
            .padding(16)
        }
    }
}

// Frise de l'éditeur d'effets : toute la vidéo sur la largeur, plages en couleur (la choisie bordée de blanc avec ses
// poignées ‹ ›), tête de lecture blanche. Glisser hors d'une poignée déplace la lecture.
struct EffectTimeline: View {
    let session: EffectsSession
    let preview: EditorPreviewPlayer
    let duration: Duration
    // Position de la poignée au début du geste (la plage bouge pendant le geste).
    @State private var handleOrigin: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.2))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                preview.pause()
                                preview.seek(to: time(at: drag.location.x, width: width))
                            }
                    )
                ForEach(session.effects) { effect in
                    segment(effect, width: width)
                }
                if let selected = session.selected {
                    handles(selected, width: width)
                }
                Rectangle()
                    .fill(.white)
                    .frame(width: 3, height: geometry.size.height + 8)
                    .shadow(radius: 2)
                    .position(x: x(of: preview.currentTime, width: width), y: geometry.size.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("effects.timeline")
    }

    private func segment(_ effect: TimedEffect, width: CGFloat) -> some View {
        let rgb = effect.effect.rgb
        let start = x(of: effect.start, width: width)
        let end = x(of: effect.end, width: width)
        return Rectangle()
            .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
            .frame(width: max(2, end - start))
            .offset(x: start)
            .onTapGesture { session.selectedID = session.selectedID == effect.id ? nil : effect.id }
            .accessibilityLabel(effect.effect.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(session.selectedID == effect.id ? .isSelected : [])
            .accessibilityIdentifier("effects.segment")
    }

    // Bordure blanche et poignées de la plage choisie.
    private func handles(_ effect: TimedEffect, width: CGFloat) -> some View {
        let start = x(of: effect.start, width: width)
        let end = x(of: effect.end, width: width)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white, lineWidth: 3)
                .frame(width: max(2, end - start) + 24)
                .offset(x: start - 12)
                .allowsHitTesting(false)
            handle(systemImage: "chevron.compact.left", label: "Début de l'effet")
                .offset(x: start - 12)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { drag in
                            let origin = handleOrigin ?? start
                            handleOrigin = origin
                            session.setStart(time(at: origin + drag.translation.width, width: width))
                        }
                        .onEnded { _ in
                            handleOrigin = nil
                            session.endInteraction()
                        }
                )
            handle(systemImage: "chevron.compact.right", label: "Fin de l'effet")
                .offset(x: end)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { drag in
                            let origin = handleOrigin ?? end
                            handleOrigin = origin
                            session.setEnd(time(at: origin + drag.translation.width, width: width))
                        }
                        .onEnded { _ in
                            handleOrigin = nil
                            session.endInteraction()
                        }
                )
        }
    }

    private func handle(systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.black.opacity(0.6))
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .background(.white)
            .contentShape(Rectangle().inset(by: -10))
            .accessibilityLabel(label)
    }

    private func x(of time: Duration, width: CGFloat) -> CGFloat {
        guard duration > .zero else { return 0 }
        return width * CGFloat(min(max(time / duration, 0), 1))
    }

    private func time(at x: CGFloat, width: CGFloat) -> Duration {
        duration * Double(min(max(x / max(width, 1), 0), 1))
    }
}
