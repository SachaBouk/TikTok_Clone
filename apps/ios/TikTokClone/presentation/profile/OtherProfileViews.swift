import MessageUI
import Observation
import SwiftUI

// Profil d'un autre compte façon TikTok (ADR-069, d'après des captures) : nom en grand et @pseudo à gauche, photo à
// droite, compteurs « Suivis · Followers · J'aime » alignés à gauche ; grand bouton « Suivre », puis deux boutons ronds :
// message (avion en papier) et « personne + », qui déplie les comptes suggérés liés à ce profil ; la flèche de partage
// (barre du haut) ouvre la feuille « Envoyer à » du profil.

// En-tête, le sien comme celui d'un autre (ADR-069, ADR-070) : nom, @pseudo (et pronoms) et compteurs à gauche, photo à
// droite, surmontée de la bulle de la note (ADR-070 : sur son profil, « À quoi penses-tu ? » sans note ; la toucher
// l'écrit). Sur le sien, le « + » de la photo la change.
struct ProfileTitleHeader: View {
    let profile: UserProfile
    let container: AppContainer
    var isOwn = false
    var changePhoto: () -> Void = {}

    // Badge « + » (ADR-073) : sur son profil, l'état de l'abonnement l'emporte (souscription faite à l'instant).
    private var isPlus: Bool { isOwn && container.plus.isActive }
    var editNote: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .plusBadge(profile.isPlus || isPlus, size: 22)
                    // Titre de l'écran pour VoiceOver (ADR-076).
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    Text("@\(profile.username)").lineLimit(1)
                    if let pronouns = profile.pronouns, !pronouns.isEmpty {
                        Text("·")
                        Text(pronouns).lineLimit(1).accessibilityIdentifier("profile.pronouns")
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                // Une phrase : « @pseudo, pronoms il/lui » (le « · » serait lu « point »).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    SpokenText.join(["@\(profile.username)", profile.pronouns.flatMap { $0.isEmpty ? nil : "pronoms \($0)" }]))
                HStack(spacing: 26) {
                    NavigationLink(value: FollowListRoute(kind: .following, username: profile.username)) {
                        counter(profile.followingCount, "Suivis")
                    }
                    .accessibilityLabel(SpokenText.count(profile.followingCount, "abonnement", "abonnements"))
                    NavigationLink(value: FollowListRoute(kind: .followers, username: profile.username)) {
                        counter(profile.followersCount, "Followers")
                    }
                    .accessibilityLabel(SpokenText.count(profile.followersCount, "abonné", "abonnés"))
                    counter(profile.likesCount, "J’aime")
                        // Nombres en entier (« 1,2 k » serait lu tel quel).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SpokenText.count(profile.likesCount, "j'aime reçu", "j'aime reçus"))
                        .accessibilityIdentifier("profile.likes")
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, hasBubble ? 26 : 0)
            VStack(spacing: -14) {
                if hasBubble {
                    ProfileNoteBubble(text: visibleNote?.text, isOwn: isOwn, action: editNote)
                        .zIndex(1)
                }
                ProfileAvatar(profile: profile, isOwn: isOwn, container: container, size: 100, changePhoto: changePhoto)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("profile.header")
    }

    private var visibleNote: ProfileNote? {
        profile.note.flatMap { $0.isVisible(at: .now) ? $0 : nil }
    }

    // Bulle sur sa photo (pour écrire une note), ou sur celle d'un autre qui en a une.
    private var hasBubble: Bool { isOwn || visibleNote != nil }

    private func counter(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value, format: .number.notation(.compactName)).font(.headline)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// Bulle de la note (ADR-070), comme TikTok : blanche, ombrée, avec deux petits ronds de « pensée » vers la photo. Sans
// note (son profil), « À quoi penses-tu ? » en gris.
struct ProfileNoteBubble: View {
    let text: String?
    let isOwn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text ?? "À quoi penses-tu ?")
                .font(.footnote)
                .foregroundStyle(text == nil ? Color.secondary : Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 128)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .offset(x: -26, y: 8)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isOwn)
        .accessibilityLabel(text.map { "Note : \($0)" } ?? "Écrire une note")
        .accessibilityIdentifier("profile.note")
    }
}

// Écrire sa note (ADR-070), dans une feuille : la bulle au-dessus de sa photo se remplit pendant la saisie, 60
// caractères, « Partager » ; « Supprimer la note » si elle existe. Visible de tous pendant 24 h.
struct ProfileNoteEditor: View {
    @Bindable var viewModel: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var cleaned: String? { ProfileRules.cleanedNote(viewModel.noteText) }
    private var isTooLong: Bool { (cleaned?.count ?? 0) > ProfileRules.maxNoteLength }
    private var hasNote: Bool { viewModel.profile?.note?.isVisible(at: .now) == true }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: -14) {
                    ProfileNoteBubble(text: cleaned, isOwn: false) {}
                        .zIndex(1)
                    AvatarView(url: viewModel.profile?.avatarURL, name: viewModel.profile?.displayName ?? "", size: 96)
                }
                .padding(.top, 8)
                TextField("À quoi penses-tu ?", text: $viewModel.noteText, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .padding(12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("noteEditor.field")
                HStack {
                    Text("Visible par tout le monde pendant 24 h")
                    Spacer()
                    Text("\(cleaned?.count ?? 0)/\(ProfileRules.maxNoteLength)")
                        .foregroundStyle(isTooLong ? Color.red : Color.secondary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if hasNote {
                    Button("Supprimer la note", role: .destructive) {
                        Task { if await viewModel.deleteNote() { dismiss() } }
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("noteEditor.delete")
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        viewModel.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Partager") {
                            Task { if await viewModel.saveNote() { dismiss() } }
                        }
                        .tint(Color.brandPink)
                        .disabled(cleaned == nil || isTooLong || cleaned == viewModel.profile?.note?.text)
                        .accessibilityIdentifier("noteEditor.share")
                    }
                }
            }
            .alert(
                "Note",
                isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear { isFocused = true }
    }
}

// Boutons : « Suivre » (rouge ; gris une fois abonné), message, et comptes suggérés (« personne + », puis ▲ une fois
// dépliés).
struct OtherProfileActions: View {
    let status: FollowStatus
    let showsSuggestions: Bool
    let follow: () -> Void
    let message: () -> Void
    let toggleSuggestions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: follow) {
                Text(status.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(status.isFollowing ? Color.primary : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(status.isFollowing ? Color(.secondarySystemFill) : Color.brandPink, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.follow")
            roundButton(systemImage: "paperplane.fill", label: "Message", action: message)
                .accessibilityIdentifier("profile.message")
            roundButton(
                systemImage: showsSuggestions ? "arrowtriangle.up.fill" : "person.fill.badge.plus",
                label: showsSuggestions ? "Masquer les comptes suggérés" : "Comptes suggérés", action: toggleSuggestions
            )
            .accessibilityIdentifier("profile.suggestions")
        }
        .padding(.horizontal, 16)
    }

    private func roundButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: systemImage.hasPrefix("arrowtriangle") ? 13 : 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// Comptes suggérés sous un profil (ADR-069) : lus à la première ouverture de la rangée ; écartés (×) sur l'appareil,
// comme les autres suggestions (ADR-058) ; comptes bloqués depuis masqués.
@MainActor
@Observable
final class ProfileSuggestionsModel {
    enum State: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var all: [AccountSuggestion] = []
    private(set) var state: State = .idle
    let username: String
    private let load: LoadProfileSuggestionsUseCase
    private let session: SessionStore

    init(username: String, load: LoadProfileSuggestionsUseCase, session: SessionStore) {
        self.username = username
        self.load = load
        self.session = session
    }

    func visible(dismissed: DismissedSuggestions, blocked: Set<String>) -> [AccountSuggestion] {
        all.filter { !dismissed.contains($0.id) && !blocked.contains($0.id) }
    }

    // Lecture lancée, attendue au plus `limit` (la rangée s'ouvre alors à sa hauteur finale) ; elle continue au-delà.
    func prepare(waitingAtMost limit: Duration) async {
        Task { await loadIfNeeded() }
        let deadline = ContinuousClock.now + limit
        while state == .idle || state == .loading, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func loadIfNeeded() async {
        guard state == .idle || state == .failed else { return }
        state = .loading
        do {
            all = try await load(username: username)
            state = .loaded
        } catch AppError.sessionExpired {
            state = .idle
            session.sessionExpired()
        } catch {
            state = .failed
        }
    }
}

// Rangée « Comptes suggérés ⓘ · Tout voir › » : cartes à faire défiler (photo, nom, raison, « Suivre », ×).
struct ProfileSuggestionsRow: View {
    let model: ProfileSuggestionsModel
    let container: AppContainer
    let openProfile: (String) -> Void
    let showAll: () -> Void
    @State private var isShowingInfo = false
    @State private var followError: String?

    private var interactions: VideoInteractionsModel { container.videoInteractions }

    var body: some View {
        let suggestions = model.visible(dismissed: container.suggestions.dismissed, blocked: interactions.blockedUserIDs)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Comptes suggérés").font(.body).foregroundStyle(.secondary)
                Button("À propos des comptes suggérés", systemImage: "info.circle") { isShowingInfo = true }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: showAll) {
                    HStack(spacing: 4) {
                        Text("Tout voir")
                        Image(systemName: "chevron.right").accessibilityHidden(true).font(.footnote.weight(.semibold))
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.suggestions.all")
            }
            .padding(.horizontal, 16)
            switch model.state {
            case .idle, .loading:
                DotsLoader().frame(maxWidth: .infinity, minHeight: 200)
            case .failed:
                Text("Impossible de charger les suggestions.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            case .loaded where suggestions.isEmpty:
                Text("Aucun compte à suggérer pour l’instant.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            case .loaded:
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(suggestions) { suggestion in
                            ProfileSuggestionCard(
                                suggestion: suggestion,
                                isFollowing: interactions.isFollowing(suggestion.user.id, loaded: false),
                                open: { openProfile(suggestion.user.username) },
                                follow: { toggleFollow(suggestion) },
                                dismiss: { withAnimation { container.suggestions.dismiss(suggestion) } }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await model.loadIfNeeded() }
        .alert("Comptes suggérés", isPresented: $isShowingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Des comptes que suit ce profil ou que suivent ses abonnés, puis des comptes populaires. Touche × pour en écarter un.")
        }
        .alert("Abonnements", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
        .accessibilityIdentifier("profile.suggestionsRow")
    }

    private func toggleFollow(_ suggestion: AccountSuggestion) {
        let following = interactions.isFollowing(suggestion.user.id, loaded: false)
        Task {
            if case .failed(let message) = await interactions.setFollowing(suggestion.user, active: !following, wasFollowing: following) {
                followError = message
            }
        }
    }
}

// Raison courte sous le nom d'une suggestion : « Te suit », « Suivi(e) par » et les photos (« +N »), ou une suggestion
// simple.
struct SuggestionReasonLine: View {
    let suggestion: AccountSuggestion
    var avatarSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 4) {
            if suggestion.followsYou {
                Text("Te suit")
            } else if !suggestion.followedBy.isEmpty {
                Text("Suivi(e) par")
                HStack(spacing: -6) {
                    ForEach(suggestion.followedBy, id: \.id) { user in
                        AvatarView(url: user.avatarURL, name: user.displayName, size: avatarSize)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    }
                }
                if suggestion.moreFollowedBy > 0 { Text("+\(suggestion.moreFollowedBy)") }
            } else {
                Text("Personnes que tu pourrais connaître")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(suggestion.carouselReason)
    }
}

private struct ProfileSuggestionCard: View {
    let suggestion: AccountSuggestion
    let isFollowing: Bool
    let open: () -> Void
    let follow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: open) {
                VStack(spacing: 8) {
                    AvatarView(url: suggestion.user.avatarURL, name: suggestion.user.displayName, size: 92)
                    Text(suggestion.user.displayName).font(.body.weight(.semibold)).lineLimit(1).plusBadge(suggestion.user.isPlus)
                    SuggestionReasonLine(suggestion: suggestion)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: follow) {
                Text(FollowStatus(following: isFollowing, followedBy: suggestion.followsYou).title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color.primary : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(isFollowing ? Color(.tertiarySystemFill) : Color.brandPink, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.suggestion.follow")
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 162)
        .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Button("Écarter @\(suggestion.user.username)", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .accessibilityIdentifier("profile.suggestion.dismiss")
        }
        .accessibilityIdentifier("profile.suggestion")
    }
}

// « Tout voir » : toutes les suggestions liées au profil, une par ligne.
struct ProfileSuggestionsListView: View {
    let model: ProfileSuggestionsModel
    let container: AppContainer
    @State private var openedProfile: ProfileRoute?
    @State private var followError: String?

    private var interactions: VideoInteractionsModel { container.videoInteractions }

    var body: some View {
        let suggestions = model.visible(dismissed: container.suggestions.dismissed, blocked: interactions.blockedUserIDs)
        List(suggestions) { suggestion in
            let following = interactions.isFollowing(suggestion.user.id, loaded: false)
            HStack(spacing: 12) {
                Button {
                    openedProfile = ProfileRoute(username: suggestion.user.username)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: suggestion.user.avatarURL, name: suggestion.user.displayName, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                            SuggestionReasonLine(suggestion: suggestion, avatarSize: 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        if case .failed(let message) = await interactions.setFollowing(
                            suggestion.user, active: !following, wasFollowing: following)
                        {
                            followError = message
                        }
                    }
                } label: {
                    Text(FollowStatus(following: following, followedBy: suggestion.followsYou).title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                        .frame(minWidth: 84, minHeight: 34)
                        .padding(.horizontal, 8)
                        .foregroundStyle(following ? Color.primary : Color.white)
                        .background(following ? Color(.systemGray5) : Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button("Écarter @\(suggestion.user.username)", systemImage: "xmark") {
                    withAnimation { container.suggestions.dismiss(suggestion) }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .overlay {
            if model.state == .loaded, suggestions.isEmpty {
                ContentUnavailableView("Aucun compte suggéré", systemImage: "person.2")
            }
        }
        .navigationTitle("Comptes suggérés")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
        .navigationDestination(item: $openedProfile) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .alert("Abonnements", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
    }
}

// Feuille « Envoyer à » d'un profil (ADR-069), comme TikTok (version réduite) :
// - ligne 1 : conversations récentes et abonnements, à choisir (coche rose) ; une fois choisis, le message et « Envoyer »
//   (carte du profil + texte, à chacun) ; la loupe ouvre la liste complète et la recherche ;
// - ligne 2 : « Copier le lien », SMS, « Plus » (feuille système) ;
// - ligne 3 : Code QR, Signaler, Bloquer (ou Débloquer), Envoyer message.
// Signaler, bloquer et écrire ferment la feuille : le profil enchaîne (`action`). En invité, tout ce qui demande un compte
// ouvre la connexion.
struct ProfileShareSheet: View {
    enum Action {
        case report, block, message, signIn
    }

    let profile: UserSummary
    let isBlocked: Bool
    let container: AppContainer
    // Collection publique partagée (ADR-072) à la place du profil : même feuille, sans Code QR ni actions sur le compte.
    var collection: VideoCollection? = nil
    let action: (Action) -> Void
    @State private var recipients: SendVideoViewModel?
    @State private var isShowingAllRecipients = false
    @State private var sentFromList = false
    @State private var isShowingQRCode = false
    @State private var isPresentingSystemSheet = false
    @State private var isComposingSMS = false
    @State private var copied = false
    @State private var unavailableMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var link: URL { collection.map { CollectionLink.url(for: $0.id) } ?? ProfileLink.url(for: profile.username) }
    private var sharedText: String {
        if let collection { return "La collection « \(collection.name) » de @\(profile.username) sur TikTok Clone : \(link.absoluteString)" }
        return "Le profil de @\(profile.username) sur TikTok Clone : \(link.absoluteString)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if container.session.isSignedIn { recipientsRow }
            if let recipients, !recipients.selected.isEmpty {
                ShareMessageComposer(model: recipients) { dismiss() }
            } else {
                linksRow
                if collection == nil { actionsRow }
            }
            Spacer(minLength: 0)
        }
        .task {
            guard container.session.isSignedIn else { return }
            let model =
                recipients ?? collection.map { container.makeSendCollectionViewModel(collection: $0) }
                ?? container.makeSendProfileViewModel(profile: profile)
            recipients = model
            await model.load()
        }
        .sheet(isPresented: $isShowingAllRecipients, onDismiss: { if sentFromList { dismiss() } }) {
            if let recipients {
                SendVideoRecipientsView(model: recipients) {
                    sentFromList = true
                    isShowingAllRecipients = false
                }
                .presentationDetents([.large])
                .presentationCornerRadius(16)
                .presentationBackground(.white)
            }
        }
        .sheet(isPresented: $isShowingQRCode) {
            NavigationStack {
                ProfileQRCodeView(session: container.session, account: profile)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer", systemImage: "xmark") { isShowingQRCode = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isPresentingSystemSheet) {
            ActivityShareSheet(items: [sharedText], allowsSendByMessage: false) { _ in isPresentingSystemSheet = false }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isComposingSMS) {
            ProfileSMSComposer(text: sharedText) { isComposingSMS = false }
                .ignoresSafeArea()
        }
        .alert(
            "Partage impossible",
            isPresented: Binding(
                get: { unavailableMessage != nil || recipients?.errorMessage != nil },
                set: {
                    if !$0 {
                        unavailableMessage = nil
                        recipients?.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unavailableMessage ?? recipients?.errorMessage ?? "")
        }
        .accessibilityIdentifier("profileShare.sheet")
    }

    private var header: some View {
        ZStack {
            Text("Envoyer à").font(.headline)
            HStack {
                if recipients != nil {
                    Button("Rechercher", systemImage: "magnifyingglass") { isShowingAllRecipients = true }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("profileShare.search")
                }
                Spacer()
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6), in: Circle())
                    .accessibilityIdentifier("profileShare.close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var recipientsRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                if let recipients {
                    ForEach(recipients.recent + recipients.others) { recipient in
                        recipientTarget(recipient, model: recipients)
                    }
                    if recipients.following.nextCursor != nil {
                        ProgressView()
                            .frame(width: 64, height: 64)
                            .onAppear { Task { await recipients.following.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 12)
    }

    private var linksRow: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ShareTarget(title: copied ? "Copié" : "Copier le lien", systemImage: copied ? "checkmark" : "link", color: .blue) { copyLink() }
                        .accessibilityIdentifier("profileShare.copyLink")
                    ShareTarget(title: "SMS", systemImage: "message.fill", color: .green) {
                        if MFMessageComposeViewController.canSendText() {
                            isComposingSMS = true
                        } else {
                            unavailableMessage = "Messages n’est pas disponible sur cet appareil."
                        }
                    }
                    .accessibilityIdentifier("profileShare.sms")
                    ShareTarget(title: "Plus", systemImage: "ellipsis", color: .blue) { isPresentingSystemSheet = true }
                        .accessibilityIdentifier("profileShare.more")
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 12)
        }
    }

    private var actionsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ShareTarget(title: "Code QR", systemImage: "qrcode", color: Color(.systemGray5), iconColor: .primary) { isShowingQRCode = true }
                .accessibilityIdentifier("profileShare.qrCode")
            ShareTarget(title: "Signaler", systemImage: "flag.fill", color: Color(.systemGray5), iconColor: .primary) { finish(.report) }
                .accessibilityIdentifier("profileShare.report")
            ShareTarget(
                title: isBlocked ? "Débloquer" : "Bloquer", systemImage: "nosign", color: Color(.systemGray5), iconColor: .primary
            ) { finish(.block) }
            .accessibilityIdentifier("profileShare.block")
            ShareTarget(title: "Envoyer message", systemImage: "paperplane.fill", color: Color(.systemGray5), iconColor: .primary) {
                finish(.message)
            }
            .accessibilityIdentifier("profileShare.message")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func recipientTarget(_ recipient: SendVideoViewModel.Recipient, model: SendVideoViewModel) -> some View {
        let isSelected = model.isSelected(recipient)
        return Button {
            model.toggle(recipient)
        } label: {
            VStack(spacing: 6) {
                ConversationAvatar(users: recipient.avatars, size: 64)
                    .opacity(isSelected ? 0.6 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if model.deliveries[recipient.id] == .sending {
                            ProgressView().frame(width: 24, height: 24).background(.white, in: Circle())
                        } else if isSelected || model.deliveries[recipient.id] == .sent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, Color.brandPink)
                                .background(.white, in: Circle())
                        }
                    }
                Text(model.deliveries[recipient.id] == .sent && !isSelected ? "Envoyé" : recipient.title)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .disabled(model.isSending)
        .accessibilityLabel("Envoyer à \(recipient.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("profileShare.recipient")
    }

    // Signaler, bloquer, écrire : en invité, la connexion ; la feuille se ferme, le profil enchaîne.
    private func finish(_ chosen: Action) {
        action(container.session.isSignedIn ? chosen : .signIn)
        dismiss()
    }

    private func copyLink() {
        UIPasteboard.general.string = sharedText
        copied = true
        Accessibility.announce("Lien copié")
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        }
    }
}

// SMS pré-rempli avec le lien du profil.
private struct ProfileSMSComposer: UIViewControllerRepresentable {
    let text: String
    let onFinish: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = text
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let onFinish: @MainActor () -> Void

        init(onFinish: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}
