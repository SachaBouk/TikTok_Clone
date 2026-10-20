import SwiftUI

// Brouillons (ADR-065) : grille de 3 colonnes, du plus récent au plus ancien, avec leur durée. Toucher rouvre la création
// sur le montage (le brouillon quitte la liste) ; appui long : supprimer (confirmation).
struct DraftsView: View {
    let drafts: DraftsModel
    let router: AppRouter
    @State private var deleting: VideoDraft?
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            if drafts.drafts.isEmpty {
                ContentUnavailableView("Aucun brouillon", systemImage: "tray", description: Text("Tes brouillons restent sur cet iPhone."))
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(drafts.drafts) { draft in
                        Button {
                            open(draft)
                        } label: {
                            Color(.secondarySystemBackground)
                                .aspectRatio(9 / 16, contentMode: .fit)
                                .overlay {
                                    if let url = drafts.thumbnailURL(of: draft), let image = UIImage(contentsOfFile: url.path(percentEncoded: false))
                                    {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text(TimelineTime.label(draft.duration))
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                        .padding(6)
                                }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = draft }
                        }
                        .accessibilityLabel(draft.description.isEmpty ? "Brouillon" : draft.description)
                        .accessibilityIdentifier("drafts.item")
                    }
                }
            }
        }
        .navigationTitle("Brouillons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { drafts.reload() }
        .confirmationDialog(
            "Supprimer ce brouillon ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let deleting { drafts.delete(deleting) }
            }
        } message: {
            Text("La vidéo et son montage seront supprimés de cet iPhone.")
        }
        .alert("Brouillons", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func open(_ draft: VideoDraft) {
        do {
            router.openCreation(draft: try drafts.open(draft))
        } catch {
            errorMessage = "Impossible d’ouvrir ce brouillon."
        }
    }
}
