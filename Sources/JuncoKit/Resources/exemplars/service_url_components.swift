// URLComponents-based API client with query parameters
import Foundation

actor PodcastSearchClient {
    private let baseURL = "https://api.podcasts.example.com"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int = 20) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "type", value: "podcast")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
