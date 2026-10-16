import Foundation
import Synchronization
import Testing
import TikTokAPI

@testable import TikTokClone

@MainActor
@Suite("Onglet Messages : activité filtrée, comptes suggérés, recherche (ADR-058)")
struct InboxTests {
    func signedInSession() async -> SessionStore {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        return session
    }

    func suggestion(_ user: UserSummary, followsYou: Bool = false, followedBy: [UserSummary] = [], count: Int = 0) -> AccountSuggestion {
        AccountSuggestion(user: user, followersCount: 3, followsYou: followsYou, followedBy: followedBy, followedByCount: count)
    }

    @Test("filtre « Activité ▾ » : tout sauf les abonnements, ou un type ; modération = deux types")
    func activityFilters() {
        #expect(!ActivityTypeFilter.all.kinds.contains(.follow))
        #expect(ActivityTypeFilter.all.kinds.count == ActivityKind.allCases.count - 1)
        // J'aime et commentaires comprennent ceux des commentaires (ADR-060).
        #expect(ActivityTypeFilter.likes.kinds == [.like, .commentLike])
        #expect(ActivityTypeFilter.comments.kinds == [.comment, .commentReply, .mention])
        #expect(ActivityTypeFilter.moderation.kinds == [.reportResolved, .contentRemoved])
        #expect(ActivityTypeFilter.comments.includes(.comment) && !ActivityTypeFilter.comments.includes(.like))
    }

    @Test("groupes filtrés : `kind` répété dans la requête, rien sans filtre")
    func groupsQuery() async throws {
        let paths = Mutex<[String]>([])
        let repository = RemoteActivityRepository(
            client: makeClient(
                transport: MockTransport { request, _ in
                    paths.withLock { $0.append(request.path ?? "") }
                    return json(.ok, #"{"items":[],"nextCursor":null}"#)
                }))
        _ = try await repository.groups(kinds: [.like, .comment], cursor: nil)
        _ = try await repository.groups(kinds: [], cursor: nil)
        let recorded = paths.withLock { $0 }
        #expect(recorded[0].contains("kind=like") && recorded[0].contains("kind=comment"))
        #expect(!recorded[1].contains("kind="))
    }

    @Test("raison d'une suggestion : « Te suit », « Suivi(e) par » et « +N », sinon une suggestion simple")
    func suggestionReason() {
        #expect(suggestion(.bob, followsYou: true, followedBy: [.alice], count: 1).reason == "Te suit")
        let followed = suggestion(.bob, followedBy: [.alice], count: 4)
        #expect(followed.reason == "Suivi(e) par")
        #expect(followed.moreFollowedBy == 3)
        #expect(suggestion(.bob).reason == "Suggéré pour toi")
    }

    @Test("suggestions écartées : sans doublon, les plus anciennes oubliées au-delà de la limite")
    func dismissedRules() {
        var dismissed = DismissedSuggestions()
        dismissed.dismiss("a")
        dismissed.dismiss("a")
        #expect(dismissed.ids == ["a"])
        for index in 0..<DismissedSuggestions.maxEntries { dismissed.dismiss("u\(index)") }
        #expect(dismissed.ids.count == DismissedSuggestions.maxEntries)
        #expect(!dismissed.contains("a"))
    }

    @Test("comptes suggérés : chargés une fois, × gardé sur l'appareil, comptes bloqués masqués, oubliés au changement de session")
    func suggestionsModel() async {
        let session = await signedInSession()
        let repository = FakeSuggestionRepository([suggestion(.alice, followsYou: true), suggestion(.bob, followedBy: [.alice], count: 1)])
        let store = InMemoryDismissedSuggestionsStore()
        let model = SuggestionsModel(load: LoadSuggestionsUseCase(suggestions: repository), store: store, session: session)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(repository.calls.withLock { $0 } == 1)
        #expect(model.visible(blocked: []).map(\.user.username) == ["alice", "bob"])
        #expect(model.visible(blocked: [UserSummary.alice.id]).map(\.user.username) == ["bob"])

        model.dismiss(model.all[1])
        #expect(model.visible(blocked: []).map(\.user.username) == ["alice"])
        #expect(store.dismissedSuggestions == [UserSummary.bob.id])
        // Relu au lancement suivant.
        let relaunched = SuggestionsModel(load: LoadSuggestionsUseCase(suggestions: repository), store: store, session: session)
        await relaunched.loadIfNeeded()
        #expect(relaunched.visible(blocked: []).map(\.user.username) == ["alice"])

        relaunched.reset()
        #expect(relaunched.all.isEmpty && relaunched.state == .idle)
        #expect(store.dismissedSuggestions.isEmpty)
    }

    @Test("suggestions par l'API : compte, « te suit », suivi par, nombre")
    func remoteSuggestions() async throws {
        let body = """
            {"items":[{"user":{"id":"u2","username":"lea","displayName":"Léa","avatarUrl":null},"followersCount":12,\
            "followsYou":false,"followedBy":[{"id":"u3","username":"tom","displayName":"Tom","avatarUrl":null}],"followedByCount":4}]}
            """
        let client = makeClient(
            transport: MockTransport { _, operation in
                operation == "listSuggestions" ? json(.ok, body) : json(.notFound, errorJSON(404, "x"))
            })
        let suggestions = try await RemoteSuggestionRepository(client: client).suggestions()
        #expect(suggestions.map(\.user.username) == ["lea"])
        #expect(suggestions[0].followersCount == 12 && !suggestions[0].followsYou)
        #expect(suggestions[0].followedBy.map(\.username) == ["tom"] && suggestions[0].moreFollowedBy == 3)

        let expired = makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) })
        await #expect(throws: AppError.sessionExpired) { try await RemoteSuggestionRepository(client: expired).suggestions() }
    }

    @Test("recherche dans les messages par l'API : texte transmis, résultats avec conversation et participants")
    func remoteMessageSearch() async throws {
        let path = Mutex<String?>(nil)
        let body = """
            {"items":[{"conversationId":"c1","messageId":"m1","content":"On va au cinéma ?","createdAt":"2026-10-15T10:00:00.000Z",\
            "participant":{"id":"u2","username":"lea","displayName":"Léa","avatarUrl":null},\
            "sender":{"id":"me","username":"moi","displayName":"Moi","avatarUrl":null}}]}
            """
        let client = makeClient(
            transport: MockTransport { request, _ in
                path.withLock { $0 = request.path }
                return json(.ok, body)
            })
        let results = try await RemoteMessagingRepository(client: client).searchMessages(query: "ciné")
        #expect(results.map(\.conversationID) == ["c1"])
        #expect(results[0].participant.username == "lea" && results[0].sender.id == "me")
        #expect(path.withLock { $0 }?.contains("/conversations/search") == true)
    }

    @Test("recherche « Compte et messages » : une seule recherche après le délai, comptes sans @, messages ; vidée avec le champ")
    func inboxSearch() async {
        let session = await signedInSession()
        let search = FakeSearchRepository()
        search.state.withLock {
            $0.accounts["lea"] = [AccountSearchPage(results: [AccountSearchResult(user: .bob, followersCount: 2, viewer: nil)], nextCursor: nil)]
        }
        let messaging = FakeMessagingRepository()
        messaging.state.withLock {
            $0.searchResults = [
                MessageSearchResult(conversationID: "c1", messageID: "m1", content: "Salut Lea", createdAt: .now, participant: .bob, sender: .bob)
            ]
        }
        let viewModel = InboxSearchViewModel(
            searchAccounts: SearchAccountsUseCase(search: search), searchMessages: SearchMessagesUseCase(messaging: messaging),
            session: session, debounce: .milliseconds(20))
        viewModel.text = "@l"
        viewModel.text = "@le"
        viewModel.text = "@lea"
        await viewModel.waitForSearch()
        #expect(search.accountQueries == ["lea"])
        #expect(messaging.state.withLock { $0.searches } == ["@lea"])
        #expect(viewModel.accounts.map(\.user.username) == ["bob"])
        #expect(viewModel.messages.isEmpty)

        viewModel.text = "salut"
        await viewModel.waitForSearch()
        #expect(viewModel.messages.map(\.messageID) == ["m1"])
        #expect(viewModel.searchedText == "salut")

        viewModel.text = "  "
        #expect(!viewModel.isSearching && viewModel.messages.isEmpty && viewModel.accounts.isEmpty)
    }
}
