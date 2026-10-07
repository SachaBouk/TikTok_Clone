import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("Cadeaux : API (ADR-050)")
struct GiftDataTests {
    @Test("catalogue et envoi : mapping, identifiant d'envoi en minuscules")
    func sendMapping() async throws {
        let log = RequestLog()
        let repository = RemoteGiftRepository(
            client: makeClient(
                transport: MockTransport { request, operation in
                    log.record(request, operation)
                    if operation == "getGiftCatalog" {
                        return json(.ok, #"{"items":[{"code":"rose","name":"Rose","emoji":"🌹","price":1}]}"#)
                    }
                    return json(
                        .created,
                        #"{"id":"g1","gift":{"code":"rose","name":"Rose","emoji":"🌹"},"amount":1,"balance":99,"createdAt":"2026-10-07T10:00:00.000Z"}"#
                    )
                }))
        #expect(try await repository.catalog() == [GiftCatalogItem(info: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), price: 1)])
        let sent = try await repository.send(videoID: "v1", giftCode: "rose", clientGiftID: UUID())
        #expect(sent == SentGift(id: "g1", gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, balance: 99))
        #expect(log.operations == ["getGiftCatalog", "sendGift"])
    }

    @Test("erreurs : 402 solde insuffisant, 429 avec délai, 403 blocage, 404 vidéo indisponible")
    func errors() async {
        let cases: [(HTTPResponse.Status, AppError)] = [
            (.init(code: 402), .insufficientBalance),
            (.forbidden, .blocked),
            (.notFound, .notFound),
            (.unauthorized, .sessionExpired),
        ]
        for (status, expected) in cases {
            let repository = RemoteGiftRepository(client: makeClient(transport: MockTransport { _, _ in json(status, errorJSON(status.code, "x")) }))
            await #expect(throws: expected) { try await repository.send(videoID: "v1", giftCode: "rose", clientGiftID: UUID()) }
        }
        let limited = RemoteGiftRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    var (response, body) = json(.tooManyRequests, errorJSON(429, "x"))
                    response.headerFields[.retryAfter] = "42"
                    return (response, body)
                }))
        await #expect(throws: AppError.tooManyActions(.gifts, retryAfter: 42)) {
            try await limited.send(videoID: "v1", giftCode: "rose", clientGiftID: UUID())
        }
    }

    @Test("portefeuille : gains, cadeau envoyé dans l'historique, cadeaux reçus")
    func walletMapping() async throws {
        let history = """
            {"items":[{"id":"t1","kind":"giftSent","amount":-50,"balanceAfter":50,"productId":null,\
            "gift":{"code":"crown","name":"Couronne","emoji":"👑","recipient":{"id":"u2","username":"bob","displayName":"Bob","avatarUrl":null}},\
            "createdAt":"2026-10-07T10:00:00.000Z"}],"nextCursor":null}
            """
        let received = """
            {"items":[{"id":"g1","gift":{"code":"rose","name":"Rose","emoji":"🌹"},"amount":1,\
            "video":{"id":"v1","thumbnailUrl":"http://cdn/v1/thumbnail.jpg"},"createdAt":"2026-10-07T10:00:00.000Z"}],"nextCursor":"g1"}
            """
        let repository = RemoteWalletRepository(
            client: makeClient(
                transport: MockTransport { _, operation in
                    operation == "listReceivedGifts" ? json(.ok, received) : json(.ok, history)
                }))
        let page = try await repository.transactions(cursor: nil)
        #expect(page.transactions[0].kind == .giftSent)
        #expect(page.transactions[0].gift?.label == "👑 Couronne")
        #expect(page.transactions[0].recipient?.username == "bob")
        let gifts = try await repository.receivedGifts(cursor: nil)
        #expect(gifts.gifts[0].sender == nil)
        #expect(gifts.gifts[0].video?.id == "v1")
        #expect(gifts.nextCursor == "g1")
    }
}

@MainActor
@Suite("Cadeaux : feuille, activité, animation (ADR-050)")
struct GiftSheetTests {
    let gifts = FakeGiftRepository()
    let walletRepository = FakeWalletRepository()
    let analyticsService = FakeAnalyticsService()

    func makeViewModel(balance: Int) async -> (GiftSheetViewModel, WalletModel) {
        let session = makeSession()
        session.signedIn(.alice)
        walletRepository.setBalance(balance)
        let analytics = makeAnalytics(analyticsService)
        let wallet = WalletModel(
            loadBalance: LoadWalletBalanceUseCase(wallet: walletRepository), purchases: FakePurchaseService(), session: session, analytics: analytics)
        let viewModel = GiftSheetViewModel(
            video: FeedVideo.sample("v1", author: "bob"), loadCatalog: LoadGiftCatalogUseCase(gifts: gifts), sendGift: SendGiftUseCase(gifts: gifts),
            wallet: wallet, session: session, analytics: analytics)
        await viewModel.load()
        return (viewModel, wallet)
    }

    @Test("chargement : catalogue et solde, premier cadeau choisi ; envoi : solde à jour, animation, mesure d'audience")
    func send() async {
        let (viewModel, wallet) = await makeViewModel(balance: 10)
        #expect(viewModel.catalog.map(\.info.code) == ["rose", "crown"])
        #expect(viewModel.selected?.info.code == "rose")
        #expect(wallet.balance == 10)

        gifts.enqueue(.success(SentGift(id: "g1", gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, balance: 9)))
        let burst = await viewModel.send()
        #expect(burst?.caption == "Rose envoyée à @bob")
        #expect(wallet.balance == 9)
        #expect(gifts.sent.map(\.video) == ["v1"])
        let event = analyticsService.events.last
        #expect(event?.name == "gift_sent")
        #expect(event?.properties["gift_code"] == .string("rose"))
        #expect(event?.properties["amount"] == .int(1))
        #expect(event?.properties["author_id"] == .string("bob-id"))
    }

    @Test("solde insuffisant : rien n'est envoyé, la feuille propose de recharger")
    func insufficientLocally() async {
        let (viewModel, _) = await makeViewModel(balance: 10)
        viewModel.select(FakeGiftRepository.catalog[1])
        #expect(viewModel.needsTopUp)
        #expect(!viewModel.isAffordable(FakeGiftRepository.catalog[1]))
        #expect(await viewModel.send() == nil)
        #expect(gifts.sent.isEmpty)
    }

    @Test("402 de l'API (solde changé ailleurs) : recharge proposée, solde relu")
    func insufficientFromAPI() async {
        let (viewModel, wallet) = await makeViewModel(balance: 10)
        walletRepository.setBalance(0)
        gifts.enqueue(.failure(.insufficientBalance))
        #expect(await viewModel.send() == nil)
        #expect(viewModel.needsTopUp)
        #expect(wallet.balance == 0)
    }

    @Test("coupure : le renvoi du même cadeau garde son identifiant d'envoi ; un autre cadeau en prend un nouveau")
    func retryKeepsClientID() async {
        let (viewModel, _) = await makeViewModel(balance: 100)
        gifts.enqueue(.failure(.network))
        _ = await viewModel.send()
        #expect(viewModel.errorMessage == AppError.network.message)
        gifts.enqueue(.success(SentGift(id: "g1", gift: GiftInfo(code: "rose", name: "Rose", emoji: "🌹"), amount: 1, balance: 99)))
        _ = await viewModel.send()
        #expect(gifts.sent.count == 2)
        #expect(gifts.sent[0].id == gifts.sent[1].id)

        viewModel.select(FakeGiftRepository.catalog[1])
        gifts.enqueue(.success(SentGift(id: "g2", gift: GiftInfo(code: "crown", name: "Couronne", emoji: "👑"), amount: 50, balance: 49)))
        _ = await viewModel.send()
        #expect(gifts.sent[2].id != gifts.sent[1].id)
    }

    @Test("activité : un cadeau seul, puis regroupés par vidéo (nombre de cadeaux, pas de comptes)")
    func activityTexts() {
        let rose = ActivityGift(name: "Rose", emoji: "🌹", amount: 1)
        let single = ActivityNotification(
            id: "n1", kind: .gift, actor: .bob, video: .init(id: "v1", thumbnailURL: nil), comment: nil, read: false, createdAt: .now, gift: rose)
        #expect(single.summary == "t’a envoyé 🌹 Rose.")
        var group = ActivityGroup.merging(single, into: nil)
        #expect(group.key == "gift:v1")
        #expect(group.actorNames == "Bob")
        #expect(group.summary == "t’a envoyé 🌹 Rose.")
        let again = ActivityNotification(
            id: "n2", kind: .gift, actor: .bob, video: .init(id: "v1", thumbnailURL: nil), comment: nil, read: false, createdAt: .now,
            gift: ActivityGift(name: "Couronne", emoji: "👑", amount: 50))
        group = ActivityGroup.merging(again, into: group)
        #expect(group.count == 2)
        #expect(group.actorNames == "Bob")
        #expect(group.summary == "t’a envoyé 2 cadeaux.")
        #expect(group.gift?.name == "Couronne")
        #expect(group.filter == ActivityFilter(kind: .gift, videoID: "v1"))
    }

    @Test("animation : accord du participe")
    func burstCaption() {
        #expect(GiftBurst(gift: GiftInfo(code: "diamond", name: "Diamant", emoji: "💎"), recipientUsername: "bob").caption == "Diamant envoyé à @bob")
        #expect(GiftBurst(gift: GiftInfo(code: "crown", name: "Couronne", emoji: "👑"), recipientUsername: "bob").caption == "Couronne envoyée à @bob")
    }
}
