import SwiftUI

// Panneau des autocollants (ADR-063), comme TikTok : onglets « Autocollants | Emoji ». « Autocollants » : la date et
// l'heure (figées à l'ajout) ; « Emoji » : une grille par catégorie, barre des catégories en bas. Un toucher ajoute
// l'autocollant au centre de la vidéo et ferme le panneau.
struct StickerPickerView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case stickers
        case emoji

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stickers: "Autocollants"
            case .emoji: "Emoji"
            }
        }
    }

    let onPick: (StickerOverlay.Kind, String) -> Void
    @State private var tab: Tab = .stickers
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider().overlay(.white.opacity(0.15))
            switch tab {
            case .stickers: stickers
            case .emoji: EmojiGrid { emoji in pick(.emoji, emoji) }
            }
        }
        .padding(.top, 18)
        .background(Color(white: 0.11).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { option in
                Button {
                    tab = option
                } label: {
                    VStack(spacing: 10) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(tab == option ? Color.white : .white.opacity(0.55))
                        Capsule().fill(tab == option ? Color.white : .clear).frame(width: 64, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityAddTraits(tab == option ? .isSelected : [])
                .accessibilityIdentifier("stickers.tab.\(option.rawValue)")
            }
        }
    }

    // Date et heure du moment : trois styles, comme les autocollants « Recommandés » de TikTok.
    private var stickers: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recommandés")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
                TimelineView(.everyMinute) { context in
                    HStack(spacing: 8) {
                        ForEach([StickerOverlay.Kind.dateSlash, .dateDash, .time], id: \.self) { kind in
                            let text = StickerOverlay.text(for: kind, at: context.date)
                            Button {
                                pick(kind, text)
                            } label: {
                                Text(text)
                                    .font(Font(StickerStyle.font(kind, size: 38) as CTFont))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            .accessibilityLabel("\(kind.title) \(text)")
                            .accessibilityIdentifier("stickers.\(kind.rawValue)")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func pick(_ kind: StickerOverlay.Kind, _ text: String) {
        onPick(kind, text)
        dismiss()
    }
}

// Grille d'emojis par catégorie, barre des catégories en bas (un toucher fait défiler jusqu'à la sienne).
struct EmojiGrid: View {
    let onPick: (String) -> Void
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(EmojiCatalog.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(section.emojis, id: \.self) { emoji in
                                    Button {
                                        onPick(emoji)
                                    } label: {
                                        Text(emoji).font(.system(size: 36))
                                    }
                                    .accessibilityIdentifier("stickers.emoji.\(emoji)")
                                }
                            }
                        }
                        .id(section.id)
                    }
                }
                .scrollTargetLayout()
                .padding(16)
            }
            .scrollPosition($position, anchor: .top)
            HStack {
                ForEach(EmojiCatalog.sections) { section in
                    Button {
                        withAnimation { position.scrollTo(id: section.id, anchor: .top) }
                    } label: {
                        Text(section.icon)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .accessibilityLabel(section.title)
                }
            }
            .padding(.horizontal, 8)
            .background(Color(white: 0.15).ignoresSafeArea(edges: .bottom))
        }
    }
}
