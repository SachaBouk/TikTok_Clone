import SwiftUI
import UIKit

// Vignettes des filtres et des effets (ADR-063) : une image de la vidéo, rendue une fois par filtre et par effet, hors du
// fil principal.
@MainActor
@Observable
final class LookThumbnailStore {
    private(set) var filters: [VideoFilter: UIImage] = [:]
    private(set) var effects: [VideoEffect: UIImage] = [:]
    private var loaded = false

    func load(from model: VideoEditorViewModel) async {
        guard !loaded, let frame = await model.previewFrame() else { return }
        loaded = true
        let (filters, effects) = await Task.detached(priority: .userInitiated) { () -> ([VideoFilter: UIImage], [VideoEffect: UIImage]) in
            guard let base = LookThumbnails.square(frame, side: 160) else { return ([:], [:]) }
            var filters: [VideoFilter: UIImage] = [:]
            for filter in VideoFilter.allCases { filters[filter] = LookThumbnails.filtered(base, filter) }
            var effects: [VideoEffect: UIImage] = [:]
            for effect in VideoEffect.allCases { effects[effect] = LookThumbnails.effected(base, effect) }
            return (filters, effects)
        }.value
        self.filters = filters
        self.effects = effects
    }
}

// Panneau des filtres, comme TikTok (ADR-063) : curseur d'intensité au-dessus (valeur affichée), puis ⊘ (aucun filtre),
// onglets des catégories et vignettes rondes ; le filtre choisi est entouré de rose.
struct FilterPanel: View {
    let model: VideoEditorViewModel
    let thumbnails: LookThumbnailStore
    @State private var category: VideoFilter.Category

    init(model: VideoEditorViewModel, thumbnails: LookThumbnailStore) {
        self.model = model
        self.thumbnails = thumbnails
        _category = State(initialValue: model.plan.filter.category ?? .portrait)
    }

    var body: some View {
        VStack(spacing: 10) {
            if model.plan.filter != .none {
                IntensitySlider(value: model.plan.filterIntensity) { value in
                    model.setFilterIntensity(value)
                } onEnded: {
                    model.endInteraction()
                }
                .padding(.horizontal, 20)
            }
            VStack(spacing: 18) {
                categories
                filters
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Color(white: 0.11)).ignoresSafeArea(edges: .bottom))
        }
        .environment(\.colorScheme, .dark)
        .task { await thumbnails.load(from: model) }
    }

    private var categories: some View {
        HStack(spacing: 0) {
            Button {
                model.setFilter(.none)
            } label: {
                Image(systemName: "nosign")
                    .font(.title2)
                    .foregroundStyle(model.plan.filter == .none ? Color.white : .white.opacity(0.6))
                    .frame(width: 52, height: 36)
            }
            .accessibilityLabel("Aucun filtre")
            .accessibilityAddTraits(model.plan.filter == .none ? .isSelected : [])
            .accessibilityIdentifier("editor.filter.none")
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 22)
            ScrollView(.horizontal) {
                HStack(spacing: 26) {
                    ForEach(VideoFilter.Category.allCases) { option in
                        Button {
                            withAnimation(.snappy) { category = option }
                        } label: {
                            VStack(spacing: 6) {
                                Text(option.title)
                                    .font(.headline)
                                    .foregroundStyle(category == option ? Color.white : .white.opacity(0.55))
                                Capsule()
                                    .fill(category == option ? Color.white : .clear)
                                    .frame(height: 2)
                            }
                            .fixedSize()
                        }
                        .accessibilityAddTraits(category == option ? .isSelected : [])
                        .accessibilityIdentifier("editor.filterCategory.\(option.rawValue)")
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.leading, 6)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(category.filters) { filter in
                    let selected = model.plan.filter == filter
                    Button {
                        model.setFilter(filter)
                    } label: {
                        VStack(spacing: 8) {
                            thumbnail(filter)
                                .frame(width: 62, height: 62)
                                .clipShape(Circle())
                                .padding(3)
                                .overlay(Circle().stroke(selected ? Color.brandPink : .clear, lineWidth: 2.5))
                            Text(filter.title)
                                .font(.subheadline)
                                .foregroundStyle(selected ? Color.brandPink : .white)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 70)
                    }
                    .accessibilityLabel(filter.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("editor.filter.\(filter.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func thumbnail(_ filter: VideoFilter) -> some View {
        if let image = thumbnails.filters[filter] {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Circle().fill(.white.opacity(0.15))
        }
    }
}

// Curseur d'intensité (0 à 100), comme TikTok : partie remplie en rose, pastille blanche, valeur au-dessus.
struct IntensitySlider: View {
    let value: Double
    let onChange: (Double) -> Void
    let onEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 28, 1)
            let x = 14 + width * value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.4)).frame(height: 3).padding(.horizontal, 14).offset(y: 12)
                Capsule().fill(Color.brandPink).frame(width: max(0, x - 14), height: 3).padding(.leading, 14).offset(y: 12)
                Circle().fill(.white).frame(width: 26, height: 26).shadow(radius: 2).position(x: x, y: 40)
                Text("\(Int((value * 100).rounded()))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .position(x: x, y: 8)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in onChange(min(max((drag.location.x - 14) / width, 0), 1)) }
                    .onEnded { _ in onEnded() }
            )
        }
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel("Intensité du filtre")
        .accessibilityValue("\(Int((value * 100).rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.1, 1))
            case .decrement: onChange(max(value - 0.1, 0))
            @unknown default: break
            }
            onEnded()
        }
        .accessibilityIdentifier("editor.filterIntensity")
    }
}

// Nom du filtre et sa catégorie en grand au milieu de la vidéo, un instant après un changement (comme TikTok).
struct FilterFlash: View {
    let filter: VideoFilter

    var body: some View {
        VStack(spacing: 2) {
            Text(filter.title).font(.system(size: 40, weight: .regular))
            if let category = filter.category {
                Text(category.title).font(.title3)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .shadow(color: .black.opacity(0.4), radius: 4)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
