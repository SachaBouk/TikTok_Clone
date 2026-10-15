import Observation
import SwiftUI

// Centres d'intérêt du compte (ADR-055), choisis à l'inscription et modifiables ici. Sans effet sur le feed pour
// l'instant (algorithme For You reporté, ADR-016).
@MainActor
@Observable
final class InterestsSettingsViewModel {
    enum State: Equatable {
        case loading, loaded, failed
    }

    private(set) var state: State = .loading
    private(set) var catalog: [Interest] = []
    private(set) var selected: Set<String> = []
    private(set) var saved: Set<String> = []
    private(set) var isSaving = false
    var errorMessage: String?

    private let loadCatalog: LoadInterestCatalogUseCase
    private let loadMine: LoadMyInterestsUseCase
    private let save: SaveInterestsUseCase
    private let session: SessionStore

    init(loadCatalog: LoadInterestCatalogUseCase, loadMine: LoadMyInterestsUseCase, save: SaveInterestsUseCase, session: SessionStore) {
        self.loadCatalog = loadCatalog
        self.loadMine = loadMine
        self.save = save
        self.session = session
    }

    var hasChanges: Bool { selected != saved }

    func load() async {
        state = .loading
        do {
            async let catalog = loadCatalog()
            async let mine = loadMine()
            self.catalog = try await catalog
            saved = Set(try await mine)
            selected = saved
            state = .loaded
        } catch {
            handle(error)
            state = .failed
        }
    }

    func toggle(_ interest: Interest) {
        if selected.contains(interest.code) { selected.remove(interest.code) } else { selected.insert(interest.code) }
    }

    // Renvoie vrai une fois enregistré.
    func saveChanges() async -> Bool {
        guard hasChanges, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            saved = Set(try await save(catalog.map(\.code).filter(selected.contains)))
            selected = saved
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func handle(_ error: any Error) {
        let error = AppError.from(error)
        if error == .sessionExpired { session.sessionExpired() } else { errorMessage = error.message }
    }
}

struct InterestsSettingsView: View {
    @State private var viewModel: InterestsSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: InterestsSettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choisis ce que tu aimes. Pour l’instant, le feed reste aléatoire.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                switch viewModel.state {
                case .loading: DotsLoader().frame(maxWidth: .infinity).padding(.top, 40)
                case .failed:
                    ContentUnavailableView {
                        Label("Impossible de charger la liste", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Réessayer") { Task { await viewModel.load() } }
                    }
                case .loaded:
                    InterestChips(catalog: viewModel.catalog, selected: viewModel.selected) { viewModel.toggle($0) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Centres d’intérêt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Enregistrer") { Task { if await viewModel.saveChanges() { dismiss() } } }
                        .disabled(!viewModel.hasChanges)
                        .accessibilityIdentifier("interests.save")
                }
            }
        }
        .task { await viewModel.load() }
        .alert(
            "Erreur", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
