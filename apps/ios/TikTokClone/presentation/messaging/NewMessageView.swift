import SwiftUI

// « Nouveau message » (bouton ✎ de la boîte de réception) : choisir un de ses abonnements. Pour écrire à un
// autre compte : le bouton « Message » de son profil.
struct NewMessageView: View {
    @State private var list: PagedList<FollowEntry>
    let select: (UserSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    init(list: PagedList<FollowEntry>, select: @escaping (UserSummary) -> Void) {
        _list = State(initialValue: list)
        self.select = select
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(list.items) { entry in
                    Button { select(entry.user) } label: {
                        UserRow(user: entry.user).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onAppear { Task { await list.loadMore(ifNeededAfter: entry) } }
                    .accessibilityIdentifier("newMessage.user")
                }
            }
            .listStyle(.plain)
            .overlay {
                PagedListPlaceholder(state: list.state, isEmpty: list.items.isEmpty, emptyTitle: "Aucun abonnement") {
                    await list.loadFirst()
                }
            }
            .navigationTitle("Nouveau message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task { await list.loadFirstIfNeeded() }
        }
    }
}
