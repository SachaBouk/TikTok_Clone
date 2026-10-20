import SwiftUI

// Sons repris des vidéos (ADR-064), comme TikTok : bandeau « ♫ » en haut de l'aperçu, panneau des sons, feuilles
// « Volume » et « Passage » (✂︎).

// Bandeau en haut de l'aperçu : « ♫ Ajouter un son », ou le son choisi et × pour le retirer.
struct SoundPill: View {
    let model: VideoEditorViewModel
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text(model.plan.sound?.sound.title ?? "Ajouter un son").lineLimit(1)
                }
            }
            .accessibilityIdentifier("editor.sound")
            if model.plan.sound != nil {
                Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 18)
                Button("Retirer le son", systemImage: "xmark") { model.setSound(nil) }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("editor.removeSound")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .frame(maxWidth: 230)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

// Panneau des sons : Recommandés, Favoris, Récents et 🔍 ; un toucher essaie le son sur la vidéo ; le son choisi a ✂︎
// (passage) et le signet (favori) ; en bas, « Son d'origine » et « Volume ».
struct SoundPanel: View {
    let model: VideoEditorViewModel
    let library: SoundLibraryModel
    let onVolume: () -> Void
    let onTrim: () -> Void
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 56)
                .padding(.horizontal, 16)
            Divider().overlay(.white.opacity(0.12))
            list
            Divider().overlay(.white.opacity(0.12))
            footer
                .frame(height: 64)
                .padding(.horizontal, 18)
        }
        .frame(height: 430)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Color(white: 0.11)).ignoresSafeArea(edges: .bottom)
        )
        .environment(\.colorScheme, .dark)
        .task { if library.items.isEmpty { library.reload() } }
        .alert("Sons", isPresented: Binding(get: { library.errorMessage != nil }, set: { _ in })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var header: some View {
        if library.isSearching {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher des sons", text: $searchText)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onChange(of: searchText) { _, text in library.search(text) }
                        .accessibilityIdentifier("sounds.searchField")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Button("Annuler") {
                    searchText = ""
                    library.closeSearch()
                }
                .foregroundStyle(.white)
            }
            .onAppear { searchFocused = true }
        } else {
            HStack(spacing: 24) {
                ForEach(SoundLibraryModel.Tab.allCases) { tab in
                    Button {
                        library.select(tab)
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.title)
                                .font(.headline)
                                .foregroundStyle(library.tab == tab ? Color.white : .white.opacity(0.55))
                            Capsule().fill(library.tab == tab ? Color.white : .clear).frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .accessibilityAddTraits(library.tab == tab ? .isSelected : [])
                    .accessibilityIdentifier("sounds.tab.\(tab.rawValue)")
                }
                Spacer()
                Button("Rechercher", systemImage: "magnifyingglass") {
                    searchText = ""
                    library.isSearching = true
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.white)
                .accessibilityIdentifier("sounds.search")
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(library.items) { sound in
                    row(sound)
                        .onAppear { if sound.id == library.items.last?.id { library.loadMore() } }
                }
                if library.isLoading {
                    ProgressView().tint(.white).padding(20)
                } else if library.items.isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(30)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyText: String {
        if library.isSearching { return library.query.isEmpty ? "Cherche un pseudo ou une description." : "Aucun son trouvé." }
        switch library.tab {
        case .recommended: return "Aucun son pour l'instant : publie une vidéo avec du son pour lancer le tien."
        case .favorites: return "Touche le signet d'un son pour le retrouver ici."
        case .recent: return "Les sons que tu utilises apparaîtront ici."
        }
    }

    private func row(_ sound: Sound) -> some View {
        let selected = model.plan.sound?.id == sound.id
        return HStack(spacing: 14) {
            Button {
                guard !selected else { return }
                Task {
                    if let chosen = await library.choose(sound) { model.setSound(chosen) }
                }
            } label: {
                HStack(spacing: 14) {
                    AsyncImage(url: sound.coverURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.12)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if library.downloadingID == sound.id { ProgressView().tint(.white) }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.white : .clear, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if selected { Image(systemName: "waveform").font(.subheadline) }
                            Text(sound.title).font(.headline).lineLimit(1)
                        }
                        Text("\(sound.author.displayName) · \(usesText(sound.usesCount)) · \(TimelineTime.label(sound.duration))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("sounds.row")
            if selected {
                Button("Choisir le passage", systemImage: "scissors", action: onTrim)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .accessibilityIdentifier("sounds.trim")
                Button(sound.favorited ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: sound.favorited ? "bookmark.fill" : "bookmark") {
                    Task { await library.toggleFavorite(sound) }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(sound.favorited ? Color.yellow : .white)
                .accessibilityIdentifier("sounds.favorite")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selected ? Color.white.opacity(0.08) : .clear)
    }

    private var footer: some View {
        HStack {
            Button {
                model.toggleMuted()
            } label: {
                Label {
                    Text("Son d'origine")
                } icon: {
                    Image(systemName: model.plan.isMuted ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(model.plan.isMuted ? Color.white : .brandPink)
                }
                .font(.title3)
            }
            .accessibilityAddTraits(model.plan.isMuted ? [] : .isSelected)
            .accessibilityIdentifier("sounds.originalSound")
            Spacer()
            Button(action: onVolume) {
                Label("Volume", systemImage: "speaker.wave.2").font(.title3)
            }
            .accessibilityIdentifier("sounds.volume")
        }
        .foregroundStyle(.white)
    }

    private func usesText(_ count: Int) -> String {
        count <= 1 ? "\(count) publication" : "\(count) publications"
    }
}

// Feuille « Volume », comme TikTok : « Terminé », puis deux grands curseurs, son d'origine et son ajouté (voix off et
// son repris), de 0 à 100 %.
struct SoundVolumePanel: View {
    let model: VideoEditorViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button("Terminé", action: onDone)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("volume.done")
            }
            Text("Son d'origine").font(.title3)
            VolumeBar(value: model.plan.isMuted ? 0 : model.plan.originalVolume, systemImage: "speaker.wave.1.fill", label: "Son d'origine") {
                value in
                if model.plan.isMuted, value > 0 { model.toggleMuted() }
                model.setOriginalVolume(value)
            } onEnded: {
                model.endInteraction()
            }
            .disabled(model.plan.isMuted && model.plan.sound == nil && model.plan.voiceovers.isEmpty)
            Text("Son ajouté").font(.title3).padding(.top, 8)
            VolumeBar(value: model.plan.addedVolume, systemImage: "music.note", label: "Son ajouté") { value in
                model.setAddedVolume(value)
            } onEnded: {
                model.endInteraction()
            }
            .disabled(model.plan.sound == nil && model.plan.voiceovers.isEmpty)
            .opacity(model.plan.sound == nil && model.plan.voiceovers.isEmpty ? 0.4 : 1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Color(white: 0.13)).ignoresSafeArea(edges: .bottom)
        )
        .environment(\.colorScheme, .dark)
    }
}

// Grand curseur de volume : partie claire jusqu'à la poignée blanche, icône à gauche.
struct VolumeBar: View {
    let value: Double
    let systemImage: String
    let label: String
    let onChange: (Double) -> Void
    let onEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.92)).frame(width: max(24, geometry.size.width * value))
                Image(systemName: systemImage).font(.title3).foregroundStyle(.gray).padding(.leading, 18)
                Capsule().fill(.white).frame(width: 18, height: 52).shadow(radius: 2).offset(x: max(0, geometry.size.width * value - 18))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in onChange(min(max(drag.location.x / geometry.size.width, 0), 1)) }
                    .onEnded { _ in onEnded() }
            )
        }
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) %")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.1, 1))
            case .decrement: onChange(max(value - 0.1, 0))
            @unknown default: break
            }
            onEnded()
        }
        .accessibilityIdentifier("volume.\(systemImage == "music.note" ? "added" : "original")")
    }
}

// Passage du son (✂︎) : début choisi au curseur ; le son couvre ensuite toute la vidéo s'il est assez long.
struct SoundTrimSheet: View {
    let model: VideoEditorViewModel
    @State private var start: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let sound = model.plan.sound {
                    let maxStart = ChosenSound.maxStart(soundDuration: sound.sound.duration, videoDuration: model.plan.outputDuration).seconds
                    Text(sound.sound.title).font(.headline)
                    if maxStart > 0 {
                        Text("Début : \(TimelineTime.label(.seconds(start)))")
                            .font(.subheadline.monospacedDigit())
                        Slider(value: $start, in: 0...maxStart)
                            .tint(Color.brandPink)
                            .accessibilityLabel("Début du son")
                            .accessibilityIdentifier("trim.slider")
                        Text(
                            "Le son joue de \(TimelineTime.label(.seconds(start))) à \(TimelineTime.label(.seconds(start) + model.plan.outputDuration))."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Ce son est plus court que la vidéo : il joue depuis le début.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Choisir le passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        model.setSoundStart(.seconds(start))
                        dismiss()
                    }
                    .accessibilityIdentifier("trim.done")
                }
            }
        }
        .onAppear { start = model.plan.sound?.start.seconds ?? 0 }
    }
}
