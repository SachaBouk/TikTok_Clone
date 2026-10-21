import SwiftUI

// Liste complète des destinataires d'une vidéo, ouverte par la loupe de la feuille « Envoyer à » (comme TikTok) :
// champ « Rechercher » (chats récents et suivis, sans casse ni accents), puis « Chats récents », « Amis » et « Suivis »
// de A à Z. Un toucher coche ou décoche la ligne ; la sélection est celle de la feuille (même modèle). Une fois des
// destinataires choisis, le message et « Envoyer » apparaissent en bas ; `onSent` après un envoi réussi.
struct SendVideoRecipientsView: View {
    @Bindable var model: SendVideoViewModel
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.isSearching {
                        searchResults
                    } else {
                        sections
                    }
                    if !model.hasLoadedAllFollowing {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            if !model.selected.isEmpty {
                ShareMessageComposer(model: model, onSent: onSent)
            }
        }
        .tint(.primary)
        .task { await model.loadAllFollowing() }
    }

    private var header: some View {
        ZStack {
            Text("Envoyer à").font(.headline)
            HStack {
                Spacer()
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("shareList.close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.primary)
            TextField("Rechercher", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("shareList.search")
            if model.isSearching {
                Button("Effacer", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = model.searchResults
        if results.isEmpty, model.hasLoadedAllFollowing {
            Text("Aucun résultat")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
        ForEach(results) { recipient in row(recipient) }
    }

    @ViewBuilder
    private var sections: some View {
        let sections = model.sections
        let firstLetterID = sections.first { if case .letter = $0.kind { true } else { false } }?.id
        // Un même compte peut paraître dans plusieurs sections : chacune a son conteneur, pour que les identifiants des
        // lignes n'y soient pas en double (sinon la pile paresseuse n'affiche pas certaines lignes).
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 0) {
                switch section.kind {
                case .recent:
                    sectionTitle("Chats récents")
                case .friends:
                    sectionTitle("Amis")
                case .letter(let letter):
                    if section.id == firstLetterID { sectionTitle("Suivis") }
                    Text(letter)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                ForEach(section.recipients) { recipient in row(recipient) }
            }
        }
        if model.hasLoadedAllFollowing, sections.isEmpty {
            Text("Suis des comptes pour leur envoyer des vidéos.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ recipient: SendVideoViewModel.Recipient) -> some View {
        let isSelected = model.isSelected(recipient)
        return Button {
            model.toggle(recipient)
        } label: {
            HStack(spacing: 14) {
                ConversationAvatar(users: recipient.avatars, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(recipient.title).font(.body.weight(.semibold)).lineLimit(1)
                        if model.isFriend(recipient) {
                            Text(" · Ami(e)s").font(.subheadline).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                        }
                    }
                    if let subtitle = subtitle(of: recipient) {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                RecipientSelectionMark(isSelected: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSending)
        .accessibilityLabel(recipient.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("shareList.recipient")
    }

    // Pseudo d'un compte, « N membres » d'un groupe.
    private func subtitle(of recipient: SendVideoViewModel.Recipient) -> String? {
        if let username = recipient.username { return username }
        return recipient.memberCount.map { "\($0) membres" }
    }
}

// Rond de sélection : vide et gris, puis plein rose avec une coche.
private struct RecipientSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, Color.brandPink)
        } else {
            Circle()
                .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                .frame(width: 28, height: 28)
        }
    }
}

// Message envoyé avec la vidéo, sous les destinataires choisis : « Écrire un message… », barre d'emojis (un toucher
// ajoute l'emoji au texte), puis le grand bouton rose « Envoyer » (« Envoyé » une fois parti, puis `onSent`).
struct ShareMessageComposer: View {
    @Bindable var model: SendVideoViewModel
    let onSent: () -> Void
    @State private var didSend = false

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            TextField("Écrire un message…", text: $model.message, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .onChange(of: model.message) { _, text in
                    if text.count > MessageRules.maxLength { model.message = String(text.prefix(MessageRules.maxLength)) }
                }
                .accessibilityIdentifier("share.message")
            HStack {
                ForEach(ShareRecipientRules.quickEmojis, id: \.self) { emoji in
                    Button(emoji) { model.appendEmoji(emoji) }
                        .font(.system(size: 32))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Ajouter \(emoji)")
                }
            }
            .padding(.horizontal, 8)
            Button {
                Task {
                    guard await model.sendSelected() else { return }
                    didSend = true
                    try? await Task.sleep(for: .milliseconds(600))
                    onSent()
                }
            } label: {
                Group {
                    if model.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Text(didSend ? "Envoyé" : "Envoyer")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSendSelected || didSend)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("share.send")
        }
        .background(.white)
    }
}
