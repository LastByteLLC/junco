// @Observable class with page-based loading and hasMore flag
import Foundation
import Observation

@Observable
class ArticleListViewModel {
    private(set) var articles: [Article] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private var currentPage = 1

    func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let newArticles = try await fetchPage(currentPage)
            articles.append(contentsOf: newArticles)
            hasMore = !newArticles.isEmpty
            currentPage += 1
        } catch {
            hasMore = false
        }
    }

    private func fetchPage(_ page: Int) async throws -> [Article] { [] }
}

struct Article: Identifiable {
    let id: Int
    let title: String
    let excerpt: String
}
