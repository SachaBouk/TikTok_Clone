import SwiftUI

// Écran de publication, comme TikTok (ADR-062) : ‹, description et couverture (première image), « # Hashtags » et
// suggestions, « Tout le monde peut voir cette publication › » et « Plus d'options › » (feuille des réglages), puis
// « Publier ». ‹ rouvre l'éditeur sur le même plan.
struct PostView: View {
    let draft: PublishDraftViewModel
    let video: PublishDraftViewModel.Draft
    let onPublished: () -> Void
    @State private var isShowingSettings = false
    @FocusState private var isEditingDescription: Bool

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
                        Button {
                            draft.insertHashtagSign()
                            isEditingDescription = true
                        } label: {
                            Label("Hashtags", systemImage: "number")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .accessibilityIdentifier("publish.hashtags")
                        Spacer()
                        Text(draft.remainingCharacters, format: .number)
                            .font(.caption)
                            .foregroundStyle(draft.remainingCharacters < 0 ? .red : .secondary)
                            .accessibilityLabel("\(draft.remainingCharacters) caractères restants")
                    }
                    .padding(.horizontal, 16)
                    hashtagSuggestions
                        .padding(.top, 10)
                    Divider().padding(.top, 16)
                    settingsRow(
                        title: draft.visibility == .onlyMe
                            ? "Toi uniquement peux voir cette publication" : "Tout le monde peut voir cette publication",
                        subtitle: nil, systemImage: draft.visibility == .onlyMe ? "lock" : "globe", identifier: "publish.visibility")
                    settingsRow(
                        title: "Plus d’options",
                        subtitle: (draft.commentsEnabled ? "Commentaires autorisés." : "Commentaires désactivés.")
                            + (draft.soundShared ? "" : " Son non partagé."),
                        systemImage: "ellipsis", identifier: "publish.moreOptions")
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("publish.submit")
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
        .sheet(isPresented: $isShowingSettings) {
            PostSettingsSheet(draft: draft)
        }
    }

    // Couverture : la première image de la vidéo (le choix d'une autre image est reporté).
    private var cover: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let preview = video.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                }
            }
            .frame(width: 110, height: 146)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                Text("Couverture")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
            }
            .accessibilityHidden(true)
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

    private func settingsRow(title: String, subtitle: String?, systemImage: String, identifier: String) -> some View {
        Button {
            isEditingDescription = false
            isShowingSettings = true
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
}

// Réglages de la publication, comme TikTok (ADR-062) : « Qui peut voir cette publication » (Tout le monde / Toi
// uniquement, ADR-061), « Définir comme audience par défaut », « Autoriser les commentaires ».
struct PostSettingsSheet: View {
    let draft: PublishDraftViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var draft = draft
        VStack(spacing: 16) {
            ZStack {
                Text("Réglages").font(.headline)
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
                VStack(spacing: 16) {
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
                    Toggle("Autoriser les commentaires", isOn: $draft.commentsEnabled)
                        .font(.headline)
                        .tint(Color.brandCyan)
                        .padding(20)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("settings.comments")
                    // ADR-064 : décoché, le son de la vidéo n'est pas proposé aux autres.
                    Toggle(isOn: $draft.soundShared) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Autoriser l'utilisation de mon son").font(.headline)
                            Text("Les autres pourront reprendre le son de cette vidéo dans les leurs.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.brandCyan)
                    .padding(20)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("settings.sound")
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .tint(.primary)
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
    }
}
