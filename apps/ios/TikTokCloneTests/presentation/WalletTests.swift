import Foundation
import Testing
import TikTokAPI
@testable import TikTokClone

@Suite("Portefeuille : API et temps réel")
struct WalletDataTests {
    @Test("solde et historique : mapping des mouvements")
    func mapping() async throws {
        let history = """
        {"items":[{"id":"t2","kind":"refund","amount":-50,"balanceAfter":50,"productId":"tokens_100","createdAt":"2026-09-27T10:00:00.000Z"},\
        {"id":"t1","kind":"purchase","amount":100,"balanceAfter":100,"productId":"tokens_100","createdAt":"2026-09-27T09:00:00.000Z"}],"nextCursor":"t1"}
        """
        let repository = RemoteWalletRepository(client: makeClient(transport: MockTransport { _, operation in
            operation == "getWallet" ? json(.ok, #"{"balance":50}"#) : json(.ok, history)
        }))
        #expect(try await repository.balance() == 50)
        let page = try await repository.transactions(cursor: nil)
        #expect(page.transactions.map(\.kind) == [.refund, .purchase])
        #expect(page.transactions.map(\.amount) == [-50, 100])
        #expect(page.transactions[0].balanceAfter == 50)
        #expect(page.nextCursor == "t1")
    }

    @Test("session expirée : 401")
    func unauthorized() async {
        let repository = RemoteWalletRepository(client: makeClient(transport: MockTransport { _, _ in
            json(.unauthorized, #"{"statusCode":401,"message":"Unauthorized"}"#)
        }))
        await #expect(throws: AppError.sessionExpired) { try await repository.balance() }
    }

    @Test("événement walletUpdated")
    func realtimeEvent() {
        let update = RealtimeEventDecoder().decode(#"{"event":"walletUpdated","data":{"balance":1200}}"#)
        #expect(update == .walletUpdated(balance: 1200))
    }
}

@MainActor
@Suite("Portefeuille : achats et crédit")
struct WalletModelTests {
    let repository = FakeWalletRepository()
    let purchases = FakePurchaseService()
    let sleeper = FakeSleeper()
    let analytics = FakeAnalyticsService()
    let session: SessionStore
    let model: WalletModel

    init() {
        session = makeSession()
        session.signedIn(.alice)
        let sleeper = sleeper
        model = WalletModel(
            loadBalance: LoadWalletBalanceUseCase(wallet: repository),
            purchases: purchases,
            session: session,
            analytics: makeAnalytics(analytics),
            sleep: { try await sleeper.sleep($0) }
        )
    }

    @Test("achat validé : attend le crédit, qui arrive par le temps réel")
    func creditByRealtime() async {
        repository.setBalance(100)
        await model.refresh()
        let model = model
        sleeper.onSleep { await MainActor.run { model.balanceChanged(600) } }

        await model.buy(FakePurchaseService.packs[1])

        #expect(model.balance == 600)
        #expect(model.lastCredit == 500)
        #expect(model.purchaseState == .idle)
        #expect(sleeper.delays.count == 1)
        #expect(analytics.eventNames == ["token_purchase_started", "token_purchase_completed"])

        // Remboursement reçu ensuite : le « +500 » disparaît.
        model.balanceChanged(100)
        #expect(model.lastCredit == nil)
    }

    @Test("crédit arrivé pendant la fermeture de la feuille de paiement : pas d'attente")
    func creditBeforePurchaseReturns() async {
        repository.setBalance(100)
        await model.refresh()
        let model = model
        purchases.duringPurchase = { model.balanceChanged(200) }

        await model.buy(FakePurchaseService.packs[0])

        #expect(model.lastCredit == 100)
        #expect(model.purchaseState == .idle)
        #expect(sleeper.delays.isEmpty)
    }

    @Test("sans événement temps réel : le solde relu finit par montrer le crédit")
    func creditByPolling() async {
        let repository = repository
        sleeper.onSleep {
            // Deuxième lecture : la première a suivi l'ouverture du paywall, sans crédit.
            if repository.reads >= 2 { repository.setBalance(100) }
        }
        await model.buy(FakePurchaseService.packs[0])
        #expect(model.lastCredit == 100)
        #expect(sleeper.delays == Array(CreditWait.pollDelays.prefix(2)))
    }

    @Test("crédit en retard : l'attente s'arrête avec un message")
    func creditLate() async {
        await model.buy(FakePurchaseService.packs[0])
        #expect(sleeper.delays == CreditWait.pollDelays)
        #expect(model.purchaseState == .idle)
        #expect(model.lastCredit == nil)
        #expect(model.message == "Achat confirmé. Tes jetons arrivent dans quelques minutes.")
    }

    @Test("achat annulé ou refusé : rien n'est attendu")
    func cancelledOrFailed() async {
        purchases.outcome = .success(.cancelled)
        await model.buy(FakePurchaseService.packs[0])
        #expect(model.purchaseState == .idle)
        #expect(sleeper.delays.isEmpty)
        #expect(analytics.eventNames == ["token_purchase_started", "token_purchase_cancelled"])

        purchases.outcome = .failure(.failed("paiement refusé"))
        await model.buy(FakePurchaseService.packs[0])
        #expect(model.message == "L’achat n’a pas abouti : paiement refusé")
        #expect(model.purchaseState == .idle)
    }

    @Test("invité : la connexion s'ouvre, aucun achat")
    func guest() async {
        await session.signOut()
        await model.buy(FakePurchaseService.packs[0])
        #expect(session.isPresentingSignIn)
        #expect(purchases.purchased.isEmpty)
    }

    @Test("packs : chargés, ou indisponibles sans clé RevenueCat")
    func packs() async {
        await model.loadPacks()
        #expect(model.packsState == .loaded)
        #expect(model.packs.map(\.productID) == ["tokens_100", "tokens_500"])

        purchases.isAvailable = false
        let unavailable = WalletModel(
            loadBalance: LoadWalletBalanceUseCase(wallet: repository),
            purchases: purchases,
            session: session,
            analytics: makeAnalytics()
        )
        await unavailable.loadPacks()
        #expect(unavailable.packsState == .failed(PurchaseError.unavailable.message))
    }

    @Test("déconnexion : état effacé, achats détachés du compte")
    func signOut() async {
        repository.setBalance(42)
        await model.refresh()
        await model.sessionChanged(userID: UserProfile.alice.id)
        await model.sessionChanged(userID: nil)
        #expect(model.balance == nil)
        #expect(purchases.users == [UserProfile.alice.id, nil])
    }

    @Test("session expirée à la lecture du solde : retour en invité")
    func sessionExpired() async {
        repository.fail(with: .sessionExpired)
        await model.refresh()
        #expect(!session.isSignedIn)
    }
}
