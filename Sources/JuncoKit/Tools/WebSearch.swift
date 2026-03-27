// WebSearch.swift — DuckDuckGo Instant Answer API integration
//
// Free, no auth needed. Returns structured answers for programming queries.
// Falls back to URL fetching if no instant answer available.

import Foundation

/// Web search result.
public struct SearchResult: Sendable {
  public let query: String
  public let answer: String?
  public let relatedTopics: [String]
  public let source: String
}

/// Web search via DuckDuckGo Instant Answer API.
public struct WebSearch: Sendable {
  private let urlFetcher = URLFetcher()

  public init() {}

  /// Search DuckDuckGo Instant Answer API.
  public func search(query: String, maxResults: Int = 3) async -> SearchResult? {
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let urlString = "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1"

    guard let url = URL(string: urlString) else { return nil }

    do {
      var request = URLRequest(url: url, timeoutInterval: 10)
      request.setValue("junco/0.3 (on-device coding agent)", forHTTPHeaderField: "User-Agent")
      let (data, _) = try await URLSession.shared.data(for: request)

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
      }

      let abstract = json["AbstractText"] as? String
      let answer = json["Answer"] as? String

      // Extract related topics
      var topics: [String] = []
      if let related = json["RelatedTopics"] as? [[String: Any]] {
        for topic in related.prefix(maxResults) {
          if let text = topic["Text"] as? String {
            topics.append(text)
          }
        }
      }

      let mainAnswer = [answer, abstract].compactMap { $0 }.first { !$0.isEmpty }

      return SearchResult(
        query: query,
        answer: mainAnswer,
        relatedTopics: topics,
        source: "DuckDuckGo"
      )
    } catch {
      return nil
    }
  }

  /// Format search results for prompt injection.
  public func formatForPrompt(_ result: SearchResult, budget: Int = 300) -> String {
    var output = "Web search: \(result.query)\n"

    if let answer = result.answer, !answer.isEmpty {
      output += "Answer: \(answer)\n"
    }

    if !result.relatedTopics.isEmpty {
      output += "Related:\n"
      for topic in result.relatedTopics {
        output += "- \(topic)\n"
      }
    }

    return TokenBudget.truncate(output, toTokens: budget)
  }
}
