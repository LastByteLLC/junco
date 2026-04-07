// Result type pattern with success and failure handling
import Foundation

enum NetworkError: Error {
    case invalidURL
    case serverError(statusCode: Int)
    case decodingFailed
}

func fetchArticle(slug: String) -> Result<String, NetworkError> {
    guard !slug.isEmpty else {
        return .failure(.invalidURL)
    }
    return .success("Article content for \(slug)")
}

let result = fetchArticle(slug: "swift-concurrency")
switch result {
case .success(let content):
    print(content)
case .failure(let error):
    switch error {
    case .invalidURL:
        print("Bad URL")
    case .serverError(let code):
        print("Server error: \(code)")
    case .decodingFailed:
        print("Decode failed")
    }
}
