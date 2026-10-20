import SwiftUI

// Écran de publication, comme TikTok (ADR-062, ADR-065) : ‹, description et couverture (« Modifier la couverture »),
// « # Hashtags » et « @ Mention » avec leurs suggestions, « Lieu » (et des lieux proches), « Tout le monde peut voir cette
// publication › » (audience), « Plus d'options › » (réglages en sections), puis « Brouillons » et « Publier ».
// ‹ rouvre l'éditeur sur le même plan.
struct PostView: View {
    let draft: PublishDraftViewModel
    let video: PublishDraftViewModel.Draft
    let container: AppContainer
    let onPublished: () -> Void
    // Brouillon enregistré : la création se ferme.
    let onDraftSaved: () -> Void
    @State private var sheet: Sheet?
    @State private var isEditingCover = false
    @State private var places: PlacePickerModel?
    @State private var isSavingDraft = false
    @FocusState private var isEditingDescription: Bool

    enum Sheet: Identifiable {
        case audience, options, location
        var id: Self { self }
    }

    var body: some View {
        @Bindable var draft = draft
        VStack(spacing: 0) {
            HStack {
                Button("Retour", systemImage: "chevron.left") { draft.editCurrent() }
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("post.back")
                Spacer()
            }
            .padding(.horizontal, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        TextField("Ajoute une description…", text: $draft.description, axis: .vertical)
                            .font(.title3)
                            .lineLimit(5...10)
                            .focused($isEditingDescription)
                            .accessibilityIdentifier("publish.description")
                        cover
                    }
                    .padding(16)
                    HStack(spacing: 10) {
                        chip("Hashtags", systemImage: "number", identifier: "publish.hashtags") {
                            draft.insertHashtagSign()
                            isEditingDescription = true
                        }
                        chip("Mention", systemImage: "at", identifier: "publish.mention") {
                            draft.insertMentionSign()
                            isEditingDescription = true
                        }
                        Spacer()
                        Text(draft.remainingCharacters, format: .number)
                            .font(.caption)
                            .foregroundStyle(draft.remainingCharacters < 0 ? .red : .secondary)
                            .accessibilityLabel("\(draft.remainingCharacters) caractères restants")
                    }
                    .padding(.horizontal, 16)
                    if !draft.mentionSuggestions.isEmpty {
                        mentionSuggestions.padding(.top, 8)
                    } else {
                        hashtagSuggestions.padding(.top, 10)
                    }
                    Divider().padding(.top, 16)
                    locationRow
                    settingsRow(
                        title: draft.visibility == .onlyMe
                            ? "Toi uniquement peux voir cette publication" : "Tout le monde peut voir cette publication",
                        subtitle: nil, systemImage: draft.visibility == .onlyMe ? "lock" : "globe", identifier: "publish.visibility"
                    ) { sheet = .audience }
                    settingsRow(title: "Plus d’options", subtitle: optionsSummary, systemImage: "ellipsis", identifier: "publish.moreOptions") {
                        sheet = .options
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: 10) {
                Button {
                    isEditingDescription = false
                    saveDraft()
                } label: {
                    Label("Brouillons", systemImage: "tray")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isSavingDraft)
                .accessibilityIdentifier("publish.drafts")
                Button {
                    isEditingDescription = false
                    if draft.publish() { onPublished() }
                } label: {
                    Label("Publier", systemImage: "sparkle")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!draft.canPublish)
                .opacity(draft.canPublish ? 1 : 0.5)
                .accessibilityIdentifier("publish.submit")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { isEditingDescription = false }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .audience: PostSettingsSheet(draft: draft, sections: .audience)
            case .options: PostSettingsSheet(draft: draft, sections: .options)
            case .location:
                if let places { LocationPickerView(model: places) { draft.location = $0 } }
            }
        }
        .fullScreenCover(isPresented: $isEditingCover) {
            CoverEditorView(video: video.file, duration: video.duration ?? .zero, choice: draft.cover) { choice, image in
                draft.setCover(choice, image: image)
                isEditingCover = false
            } onCancel: {
                isEditingCover = false
            }
        }
        .task {
            if places == nil { places = container.makePlacePicker() }
            await places?.loadNearby()
        }
    }

    private var optionsSummary: String {
        var parts = [draft.commentsEnabled ? "Commentaires autorisés." : "Commentaires désactivés."]
        if !draft.soundShared { parts.append("Son non partagé.") }
        if draft.aiGenerated { parts.append("Contenu généré par l’IA.") }
        if draft.saveToDevice { parts.append("Enregistrée sur l’iPhone.") }
        return parts.joined(separator: " ")
    }

    // Couverture : l'image choisie (ou la première image), « Modifier la couverture » ouvre son écran.
    private var cover: some View {
        Button {
            isEditingDescription = false
            isEditingCover = true
        } label: {
            Color(.secondarySystemBackground)
                .overlay {
                    if let image = draft.coverImage ?? video.preview {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: 110, height: 146)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    Text("Modifier la couverture")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                }
        }
        .buttonStyle(.plain)
        .disabled(video.duration == nil)
        .accessibilityLabel("Modifier la couverture")
        .accessibilityIdentifier("publish.cover")
    }

    // « Lieu » : le lieu choisi (× le retire), ou la page « Ajouter un lieu » ; lieux proches en pastilles si la
    // localisation est déjà autorisée.
    @ViewBuilder
    private var locationRow: some View {
        if let location = draft.location {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse").font(.title3).frame(width: 28)
                Text(location.name).font(.title3).lineLimit(1)
                Spacer()
                Button("Retirer le lieu", systemImage: "xmark") { draft.location = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("publish.location.remove")
            }
            .padding(16)
        } else {
            settingsRow(title: "Lieu", subtitle: nil, systemImage: "mappin.and.ellipse", identifier: "publish.location") {
                sheet = .location
            }
            if let nearby = places?.nearby, !nearby.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(nearby.prefix(6)) { place in
                            Button(place.name) { draft.location = place }
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.leading, 58)
                    .padding(.trailing, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 8)
                .accessibilityIdentifier("publish.nearbyPlaces")
            }
        }
    }

    private func chip(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityIdentifier(identifier)
    }

    // Suggestions en écrivant « # » (ADR-049) : toucher complète le hashtag en cours de saisie.
    @ViewBuilder
    private var hashtagSuggestions: some View {
        if !draft.hashtagSuggestions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(draft.hashtagSuggestions) { hashtag in
                        Button {
                            draft.applySuggestion(hashtag)
                        } label: {
                            Text("\(hashtag.title) · \(hashtag.videosCount.formatted(.number.notation(.compactName)))")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("\(hashtag.title), \(hashtag.videosLabel)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("publish.hashtagSuggestions")
        }
    }

    // Suggestions en écrivant « @ » (ADR-065) : toucher complète la mention.
    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(draft.mentionSuggestions, id: \.id) { user in
                Button {
                    draft.applyMention(user)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: user.avatarURL, name: user.displayName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.headline).foregroundStyle(.primary)
                            Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("publish.mention.\(user.username)")
            }
        }
        .accessibilityIdentifier("publish.mentionSuggestions")
    }

    private func settingsRow(title: String, subtitle: String?, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            isEditingDescription = false
            action()
        } label: {
            HStack(alignment: subtitle == nil ? .center : .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }

    private func saveDraft() {
        isSavingDraft = true
        Task {
            if await draft.saveCurrentDraft() { onDraftSaved() }
            isSavingDraft = false
        }
    }
}

// Réglages de la publication, comme TikTok (ADR-062, ADR-065) : « Qui peut voir cette publication » (Tout le monde / Toi
// uniquement, ADR-061) avec « Définir comme audience par défaut » ; « Plus d'options » en sections : Confidentialité
// (commentaires, son) et Réglages avancés (contenu généré par l'IA, enregistrer sur l'appareil). Le ⚙ de l'éditeur
// montre tout.
struct PostSettingsSheet: View {
    struct Sections: OptionSet {
        let rawValue: Int
        static let audience = Sections(rawValue: 1)
        static let options = Sections(rawValue: 2)
        static let all: Sections = [.audience, .options]
    }

    let draft: PublishDraftViewModel
    var sections: Sections = .all
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var draft = draft
        VStack(spacing: 16) {
            ZStack {
                Text(sections == .options ? "Plus d’options" : "Réglages").font(.headline)
                HStack {
                    Spacer()
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("settings.close")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sections.contains(.audience) { audience }
                    if sections.contains(.options) {
                        sectionTitle("Confidentialité")
                        VStack(spacing: 0) {
                            toggleRow(
                                "Autoriser les commentaires", systemImage: "bubble.left", isOn: $draft.commentsEnabled,
                                identifier: "settings.comments")
                            Divider().padding(.leading, 56)
                            // ADR-064 : décoché, le son de la vidéo n'est pas proposé aux autres.
                            toggleRow(
                                "Autoriser l'utilisation de mon son", systemImage: "music.note", isOn: $draft.soundShared,
                                detail: "Les autres pourront reprendre le son de cette vidéo dans les leurs.", identifier: "settings.sound")
                        }
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        sectionTitle("Réglages avancés")
                        VStack(spacing: 0) {
                            toggleRow(
                                "Contenu généré par l'IA", systemImage: "sparkles", isOn: $draft.aiGenerated,
                                detail: "Ajoute cette étiquette pour indiquer que ta vidéo a été créée ou modifiée avec l’IA.",
                                identifier: "settings.aiGenerated")
                            Divider().padding(.leading, 56)
                            toggleRow(
                                "Enregistrer sur l'appareil", systemImage: "square.and.arrow.down",
                                isOn: Binding(get: { draft.saveToDevice }, set: { value in Task { await draft.setSaveToDevice(value) } }),
                                detail: "La vidéo publiée est aussi copiée dans Photos.", identifier: "settings.saveToDevice")
                        }
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .presentationDetents(sections == .audience ? [.medium] : [.medium, .large])
        .alert(
            "Réglages", isPresented: Binding(get: { draft.errorMessage != nil }, set: { if !$0 { draft.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(draft.errorMessage ?? "")
        }
    }

    private var audience: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Qui peut voir cette publication").font(.headline).padding(.bottom, 8)
            ForEach(VideoVisibility.allCases, id: \.self) { visibility in
                Button {
                    draft.visibility = visibility
                } label: {
                    HStack {
                        Text(visibility.label).foregroundStyle(.primary)
                        if visibility == draft.defaultVisibility {
                            Text("(Par défaut)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: draft.visibility == visibility ? "largecircle.fill.circle" : "circle")
                            .font(.title2)
                            .foregroundStyle(draft.visibility == visibility ? Color.brandPink : Color(.systemGray3))
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(draft.visibility == visibility ? .isSelected : [])
                .accessibilityIdentifier("settings.visibility.\(visibility.rawValue)")
            }
            Button("Définir comme audience par défaut") { draft.makeVisibilityDefault() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6), in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .disabled(draft.visibility == draft.defaultVisibility)
                .opacity(draft.visibility == draft.defaultVisibility ? 0.5 : 1)
                .accessibilityIdentifier("settings.defaultAudience")
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 4)
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>, detail: String? = nil, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage).font(.title3).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(Color.brandCyan)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityIdentifier(identifier)
    }
}
