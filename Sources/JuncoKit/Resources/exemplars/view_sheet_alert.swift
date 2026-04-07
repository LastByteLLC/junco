// View with .sheet and .alert modifiers
import SwiftUI

struct BookmarkListView: View {
    @State private var showAddSheet = false
    @State private var showDeleteAlert = false
    @State private var selectedBookmark: Bookmark?

    var body: some View {
        List {
            Button("Add Bookmark") { showAddSheet = true }
        }
        .sheet(isPresented: $showAddSheet) {
            AddBookmarkView()
                .presentationDetents([.medium])
        }
        .alert("Delete Bookmark?",
               isPresented: $showDeleteAlert,
               presenting: selectedBookmark) { bookmark in
            Button("Delete", role: .destructive) { delete(bookmark) }
            Button("Cancel", role: .cancel) { }
        } message: { bookmark in
            Text("Remove \"\(bookmark.title)\" from your bookmarks?")
        }
    }

    private func delete(_ bookmark: Bookmark) { }
}

struct Bookmark: Identifiable {
    let id: UUID
    let title: String
}

struct AddBookmarkView: View {
    var body: some View { Text("Add") }
}
