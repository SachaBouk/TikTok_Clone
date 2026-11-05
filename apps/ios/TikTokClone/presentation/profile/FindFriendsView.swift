import AVFoundation
import Observation
import SwiftUI
import VisionKit

// « Trouver des amis » (ADR-070), ouvert par « personne + » de son profil, comme TikTok : recherche de comptes (ADR-049),
// « Utiliser un code QR » (son code, ADR-057), « Inviter des ami(e)s » (lien du profil), puis les comptes suggérés
// (ADR-058, ADR-068) avec les trois dernières vidéos de chacun. En haut à droite, le scanner de codes QR. Hors
// périmètre : « Entrer en contact », Contacts, Facebook.
@MainActor
@Observable
final class FindFriendsModel {
    var query = ""
    private(set) var results: [AccountSearchResult] = []
    private(set) var isSearching = false
    private(set) var searchFailed = false
    // Première page de la grille de chaque compte suggéré (trois miniatures), par pseudo.
    private(set) var videos: [String: FeedPage] = [:]
    private var loadingVideos: Set<String> = []

    private let searchAccounts: SearchAccountsUseCase
    private let loadVideos: LoadVideoPageUseCase
    private let session: SessionStore

    init(searchAccounts: SearchAccountsUseCase, loadVideos: LoadVideoPageUseCase, session: SessionStore) {
        self.searchAccounts = searchAccounts
        self.loadVideos = loadVideos
        self.session = session
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces).replacing(/^@/, with: "")
    }

    // Recherche lancée 300 ms après la dernière frappe (tâche relancée à chaque changement) ; son propre compte écarté.
    func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = []
            searchFailed = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await searchAccounts(query: text, cursor: nil)
            guard !Task.isCancelled else { return }
            results = page.results.filter { $0.user.id != session.profile?.id }
            searchFailed = false
        } catch is CancellationError {
        } catch AppError.sessionExpired {
            session.sessionExpired()
        } catch {
            searchFailed = true
        }
    }

    // Vidéos d'un compte suggéré, lues une fois quand sa ligne apparaît (échec : pas de miniatures).
    func loadVideos(of username: String) async {
        guard videos[username] == nil, !loadingVideos.contains(username) else { return }
        loadingVideos.insert(username)
        defer { loadingVideos.remove(username) }
        if let page = try? await loadVideos(.accountVideos(username: username), cursor: nil) {
            videos[username] = page
        }
    }
}

struct FindFriendsView: View {
    @State private var model: FindFriendsModel
    let container: AppContainer
    @Environment(\.navigationPath) private var navigationPath
    @State private var isScanning = false
    @State private var isShowingInfo = false
    @State private var followError: String?

    init(model: FindFriendsModel, container: AppContainer) {
        _model = State(initialValue: model)
        self.container = container
    }

    private var interactions: VideoInteractionsModel { container.videoInteractions }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                if model.trimmedQuery.isEmpty {
                    actions
                    suggestions
                } else {
                    searchResults
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Trouver des amis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scanner un code QR", systemImage: "qrcode.viewfinder") { isScanning = true }
                    .accessibilityIdentifier("findFriends.scan")
            }
        }
        .task(id: model.query) { await model.search() }
        .task { await container.suggestions.loadIfNeeded() }
        .fullScreenCover(isPresented: $isScanning) {
            QRCodeScannerView { username in
                isScanning = false
                navigationPath?.wrappedValue.append(ProfileRoute(username: username))
            }
        }
        .alert("Comptes suggérés", isPresented: $isShowingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Des comptes que suivent les personnes que tu suis, des personnes qui te suivent et des comptes populaires. Touche × pour en écarter un."
            )
        }
        .alert("Abonnements", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher par nom ou nom d'utilisateur", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("findFriends.search")
            if !model.query.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // « Utiliser un code QR » et « Inviter des ami(e)s ».
    @ViewBuilder
    private var actions: some View {
        Button {
            navigationPath?.wrappedValue.append(AccountRoute.qrCode)
        } label: {
            ActionRow(
                title: "Utiliser un code QR", subtitle: "Affiche ou scanne les codes QR d'autres personnes.", systemImage: "qrcode",
                color: .orange)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("findFriends.qrCode")
        if let username = container.session.profile?.username {
            ShareLink(item: ProfileLink.url(for: username), message: Text("Retrouve-moi sur TikTok Clone")) {
                ActionRow(
                    title: "Inviter des ami(e)s", subtitle: "Partage ton profil pour permettre aux autres de te trouver.",
                    systemImage: "arrowshape.turn.up.right.fill", color: Color(red: 0.95, green: 0.7, blue: 0.0))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("findFriends.invite")
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let suggestions = container.suggestions.visible(blocked: interactions.blockedUserIDs)
        if !suggestions.isEmpty {
            HStack(spacing: 6) {
                Text("Comptes suggérés").font(.title3.bold())
                Button("À propos des comptes suggérés", systemImage: "info.circle") { isShowingInfo = true }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
            ForEach(suggestions) { suggestion in
                FindFriendsSuggestionRow(
                    suggestion: suggestion,
                    isFollowing: interactions.isFollowing(suggestion.user.id, loaded: false),
                    videos: model.videos[suggestion.user.username],
                    open: { navigationPath?.wrappedValue.append(ProfileRoute(username: suggestion.user.username)) },
                    openVideo: { page, index in
                        navigationPath?.wrappedValue.append(
                            VideoPlayerRoute(list: .accountVideos(username: suggestion.user.username), page: page, startIndex: index))
                    },
                    toggleFollow: { toggleFollow(suggestion.user, followedBy: suggestion.followsYou) },
                    dismiss: { withAnimation { container.suggestions.dismiss(suggestion) } }
                )
                .task { await model.loadVideos(of: suggestion.user.username) }
                if suggestion.id != suggestions.last?.id {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.results.isEmpty {
            Group {
                if model.isSearching {
                    ProgressView()
                } else if model.searchFailed {
                    Text("La recherche n'a pas abouti. Vérifie ta connexion.")
                } else {
                    Text("Aucun compte trouvé")
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
        ForEach(model.results) { result in
            let status = FollowStatus(
                following: interactions.isFollowing(result.user.id, loaded: result.viewer?.following ?? false),
                followedBy: result.viewer?.followedBy ?? false)
            HStack(spacing: 12) {
                Button {
                    navigationPath?.wrappedValue.append(ProfileRoute(username: result.user.username))
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: result.user.avatarURL, name: result.user.displayName, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                            Text("@\(result.user.username)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                FollowButton(status: status) {
                    toggleFollow(result.user, followedBy: result.viewer?.followedBy ?? false, loaded: result.viewer?.following ?? false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("findFriends.result")
        }
    }

    private func toggleFollow(_ user: UserSummary, followedBy: Bool, loaded: Bool = false) {
        let following = interactions.isFollowing(user.id, loaded: loaded)
        Task {
            if case .failed(let message) = await interactions.setFollowing(user, active: !following, wasFollowing: following) {
                followError = message
            }
        }
    }
}

// Ligne d'action : rond de couleur avec son icône, titre, sous-titre et chevron.
private struct ActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").accessibilityHidden(true).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// Compte suggéré : photo, nom, @pseudo, raison, « Suivre » et × ; dessous, ses trois dernières vidéos (s'il en a).
private struct FindFriendsSuggestionRow: View {
    let suggestion: AccountSuggestion
    let isFollowing: Bool
    let videos: FeedPage?
    let open: () -> Void
    let openVideo: (FeedPage, Int) -> Void
    let toggleFollow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        AvatarView(url: suggestion.user.avatarURL, name: suggestion.user.displayName, size: 68)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.user.displayName).font(.body.weight(.bold)).lineLimit(1)
                            Text("@\(suggestion.user.username)").font(.subheadline).lineLimit(1)
                            SuggestionReasonLine(suggestion: suggestion, avatarSize: 18)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("findFriends.suggestion")
                Button(action: toggleFollow) {
                    Text(FollowStatus(following: isFollowing, followedBy: suggestion.followsYou).title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 88)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .foregroundStyle(isFollowing ? Color.primary : Color.white)
                        .background(isFollowing ? Color(.systemGray5) : Color.brandPink, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("findFriends.follow")
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.body).foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Écarter @\(suggestion.user.username)")
            }
            if let videos, !videos.videos.isEmpty {
                thumbnails(videos)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func thumbnails(_ page: FeedPage) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(page.videos.prefix(3).enumerated()), id: \.element.id) { index, video in
                Button {
                    openVideo(page, index)
                } label: {
                    Color(.secondarySystemBackground)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { CachedThumbnail(url: video.thumbnailURL) }
                        .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vidéo de @\(suggestion.user.username)")
            }
            ForEach(0..<max(0, 3 - page.videos.count), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.trailing, 72)
    }
}

// Scanner de codes QR (ADR-070) : la caméra lit un lien de profil (`tiktokclone://users/<pseudo>`) et ouvre ce profil.
// Sans caméra (simulateur) ou sans autorisation : un message à la place.
struct QRCodeScannerView: View {
    let onProfile: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var unknownCode = false

    private var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !isSupported {
                unavailable("Scanner indisponible", "Le scanner de codes QR a besoin de la caméra d'un iPhone.")
            } else if access == .authorized {
                QRDataScanner { payload in
                    guard let url = URL(string: payload), let username = ProfileLink.username(from: url) else {
                        unknownCode = true
                        return
                    }
                    onProfile(username)
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 240, height: 240)
                VStack {
                    Spacer()
                    Text(unknownCode ? "Ce code QR n'est pas un profil TikTok Clone." : "Scanne le code QR d'un profil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 60)
                }
            } else if access == .notDetermined {
                ProgressView().tint(.white)
            } else {
                unavailable("Caméra non autorisée", "Autorise la caméra dans les Réglages pour scanner un code QR.")
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Fermer", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(20)
                .accessibilityIdentifier("scanner.close")
        }
        .task {
            guard isSupported, access == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView(title, systemImage: "qrcode.viewfinder", description: Text(message))
            .foregroundStyle(.white)
    }
}

// `DataScannerViewController` (VisionKit) limité aux codes QR ; chaque code reconnu est passé une fois.
private struct QRDataScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var seen: Set<String> = []

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, seen.insert(payload).inserted else { continue }
                onCode(payload)
            }
        }
    }
}
