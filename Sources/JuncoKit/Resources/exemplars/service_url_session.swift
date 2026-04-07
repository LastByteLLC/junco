// Actor with async URLSession fetch and JSON decoding
import Foundation

actor ArticleService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchArticles(from url: URL) async throws -> [Article] {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode([Article].self, from: data)
    }
}

struct Article: Codable, Identifiable {
    let id: Int
    let title: String
    let authorName: String
}
