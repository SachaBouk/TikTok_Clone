import Photos
import SwiftUI

// Galerie maison de la création, comme TikTok (ADR-062) : × et « Récents ⌄ » (albums), onglets, grille à trois colonnes
// avec la durée des vidéos et un rond de sélection numéroté, puis en bas « Sélectionner plusieurs » et « Suivant », ou
// le bandeau des vidéos choisies (× pour en retirer une) et « Suivant (N) ».
struct GalleryPickerView: View {
    @State private var model: GalleryViewModel
    let onDone: ([LibraryAsset]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(model: GalleryViewModel, onDone: @escaping ([LibraryAsset]) -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            content
            footer
        }
        .background(Color(.systemBackground))
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload() } }
        }
        .alert(
            "Galerie",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack {
            Menu {
                Button("Récents") { Task { await model.select(album: nil) } }
                ForEach(model.albums) { album in
                    Button("\(album.title) (\(album.count))") { Task { await model.select(album: album) } }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.albumTitle).font(.title3.bold())
                    Image(systemName: "chevron.down").font(.subheadline.bold())
                }
                .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("gallery.album")
            HStack {
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("gallery.close")
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // Onglets soulignés ; en mode Caméra, « Vidéos » seul.
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(model.filters) { filter in
                Button {
                    Task { await model.select(filter: filter) }
                } label: {
                    VStack(spacing: 10) {
                        Text(filter.title)
                            .font(.headline)
                            .foregroundStyle(model.filter == filter ? .primary : .secondary)
                        Rectangle()
                            .fill(model.filter == filter ? Color.primary : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
            }
        }
        .frame(maxWidth: model.filters.count == 1 ? 140 : .infinity)
        .frame(maxWidth: .infinity, alignment: model.filters.count == 1 ? .center : .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .denied:
            ContentUnavailableView {
                Label("Accès aux Photos refusé", systemImage: "photo.on.rectangle")
            } description: {
                Text("Autorise l’accès à tes photos dans les Réglages pour publier une vidéo de ta galerie.")
            } actions: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Ouvrir les Réglages") { openURL(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandPink)
                }
            }
            .frame(maxHeight: .infinity)
        case .notDetermined:
            ProgressView().frame(maxHeight: .infinity)
        case .full, .limited:
            VStack(spacing: 0) {
                if model.access == .limited { limitedBanner }
                if model.assets.isEmpty, !model.isLoading {
                    ContentUnavailableView(
                        model.filter == .photos ? "Aucune photo" : "Aucune vidéo", systemImage: "photo.on.rectangle",
                        description: Text(model.access == .limited ? "Ajoute des médias à ceux que l’app peut voir." : "Ta galerie est vide.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    grid
                }
            }
        }
    }

    // Accès limité : « Gérer » ouvre le choix des photos que l'app peut voir.
    private var limitedBanner: some View {
        HStack {
            Text("Tu as autorisé l’accès à certaines photos seulement.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Gérer") { presentLimitedPicker() }
                .font(.footnote.bold())
                .tint(Color.brandPink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var grid: some View {
        GeometryReader { geometry in
            let side = (geometry.size.width - 2) / 3
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 1), count: 3), spacing: 1) {
                    ForEach(model.assets) { asset in
                        GalleryCell(
                            asset: asset, image: model.thumbnails[asset.id], number: model.number(of: asset),
                            showsSelection: model.selectsMultiple && asset.isVideo
                        )
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !model.toggle(asset) { onDone(model.selection) }
                        }
                        .task { await model.loadThumbnail(of: asset, side: side * 2) }
                    }
                }
            }
        }
        .accessibilityIdentifier("gallery.grid")
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            if model.canContinue, model.selectsMultiple {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(model.selection) { asset in
                            SelectedThumbnail(asset: asset, image: model.thumbnails[asset.id]) { model.remove(asset) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 12) {
                if model.kind == .video, !model.canContinue {
                    Button {
                        model.setSelectsMultiple(!model.selectsMultiple)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: model.selectsMultiple ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(model.selectsMultiple ? Color.brandPink : .secondary)
                            Text("Sélectionner plusieurs")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .fixedSize()
                    }
                    .accessibilityIdentifier("gallery.multiple")
                }
                Button {
                    onDone(model.selection)
                } label: {
                    Text(model.selection.count > 1 ? "Suivant (\(model.selection.count))" : "Suivant")
                        .font(.headline)
                        .foregroundStyle(model.canContinue ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.canContinue ? Color.brandPink : Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!model.canContinue)
                .accessibilityIdentifier("gallery.next")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.systemBackground))
    }

    private func presentLimitedPicker() {
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            var controller = scene.keyWindow?.rootViewController
        else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in
            Task { @MainActor in await model.reload() }
        }
    }
}

// Case de la grille : miniature, durée d'une vidéo, rond de sélection (numéro rose une fois choisie).
private struct GalleryCell: View {
    let asset: LibraryAsset
    let image: CGImage?
    let number: Int?
    let showsSelection: Bool

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let duration = asset.duration {
                    Text(GalleryDuration.label(duration))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsSelection {
                    ZStack {
                        if let number {
                            Circle().fill(Color.brandPink)
                            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white)
                        } else {
                            Circle().fill(.black.opacity(0.15))
                            Circle().stroke(.white, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(6)
                }
            }
            .overlay {
                if number != nil { Color.white.opacity(0.2) }
            }
            .accessibilityElement()
            .accessibilityLabel(asset.isVideo ? "Vidéo, \(GalleryDuration.label(asset.duration ?? .zero))" : "Photo")
            .accessibilityValue(number.map { "Choisie, \($0)" } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("gallery.asset")
    }
}

// Vidéo du bandeau : miniature, durée, × pour la retirer.
private struct SelectedThumbnail: View {
    let asset: LibraryAsset
    let image: CGImage?
    let onRemove: () -> Void

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
            .frame(width: 66, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) {
                if let duration = asset.duration {
                    Text(GalleryDuration.label(duration))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button("Retirer", systemImage: "xmark", action: onRemove)
                    .labelStyle(.iconOnly)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.5), in: Circle())
                    .offset(x: 4, y: -4)
            }
    }
}

// « 00:50 », « 02:17 » : minutes et secondes, comme la galerie de TikTok.
enum GalleryDuration {
    static func label(_ duration: Duration) -> String {
        let seconds = Int(duration.seconds.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
