// View with .searchable modifier and filtered list
import SwiftUI

struct ArticleSearchView: View {
    let articles: [Article]
    @State private var searchText = ""

    var filtered: [Article] {
        guard !searchText.isEmpty else { return articles }
        return articles.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { article in
                VStack(alignment: .leading) {
                    Text(article.title).font(.headline)
                    Text(article.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Articles")
            .searchable(text: $searchText, prompt: "Search articles")
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}

struct Article: Identifiable {
    let id: UUID
    let title: String
    let summary: String
}
