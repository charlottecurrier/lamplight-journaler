import SwiftUI

/// Entries you marked with a ribbon, from every journal, newest first.
struct FavoritesScreen: View {
    @Environment(AppModel.self) private var model

    @Binding var selection: UUID?
    var onCompose: (NewEntryChoice) -> Void

    var body: some View {
        let favorites = model.favorites

        List(selection: $selection) {
            ForEach(favorites) { entry in
                EntryRow(entry: entry, showJournal: model.journals.count > 1)
                    .tag(entry.id)
                    .entryRowStyle(selected: selection == entry.id)
                    .entryActions(entry, selection: $selection)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Favorites")
        .composeToolbar(onCompose)
        .overlay {
            if favorites.isEmpty {
                EmptyStateView(
                    systemImage: "bookmark",
                    title: "No favorites yet",
                    message: "Tap the ribbon on an entry, or swipe an entry to the right, to keep it here."
                )
            }
        }
    }
}
