// URLFetcher.swift — Extract and fetch URLs from user input
//
// Detects URLs in queries, upgrades HTTP to HTTPS, fetches content
// via URLSession, strips HTML to plain text, and truncates to budget.
// All on-device, no WKWebView needed.

import Foundation

/// A fetched URL with its extracted text content.
public struct FetchedURL: Sendable {
  public let url: String
  public let title: String?
  public let content: String
  public let bytesFetched: Int
}

/// Extracts URLs from text and fetches their content.
public struct URLFetcher: Sendable {
  /// Maximum bytes to download per URL (256KB).
  private static let maxBytes = 256 * 1024

  /// Timeout per fetch in seconds.
  private static let timeout: TimeInterval = 10

  public init() {}

  // MARK: - URL Extraction

  /// Extract all URLs from input text, upgrading HTTP to HTTPS.
  public func extractURLs(from text: String) -> [URL] {
    let pattern = /https?:\/\/[^\s<>"')\]]+/
    return text.matches(of: pattern).compactMap { match in
      var urlString = String(match.0)
      // Trim trailing punctuation that's likely not part of the URL
      while let last = urlString.last, [",", ".", ";", ":", "!", "?"].contains(String(last)) {
        urlString.removeLast()
      }
      // Upgrade HTTP to HTTPS
      if urlString.hasPrefix("http://") {
        urlString = "https://" + urlString.dropFirst(7)
      }
      return URL(string: urlString)
    }
  }

  /// Strip URLs from input text, returning clean query + extracted URLs.
  public func separateURLs(from text: String) -> (query: String, urls: [URL]) {
    let urls = extractURLs(from: text)
    var clean = text
    for url in urls {
      // Remove both http and https versions
      let httpsStr = url.absoluteString
      let httpStr = httpsStr.replacingOccurrences(of: "https://", with: "http://")
      clean = clean.replacingOccurrences(of: httpsStr, with: "")
      clean = clean.replacingOccurrences(of: httpStr, with: "")
    }
    clean = clean.replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (clean, urls)
  }

  // MARK: - Fetching

  /// Fetch content from a URL, returning extracted text.
  public func fetch(url: URL, maxTokens: Int = 500) async -> FetchedURL? {
    // Only fetch HTTPS
    guard url.scheme == "https" else { return nil }

    var request = URLRequest(url: url, timeoutInterval: Self.timeout)
    // Prefer plain text; accept HTML as fallback
    request.setValue("text/plain, text/html;q=0.9, application/json;q=0.8", forHTTPHeaderField: "Accept")
    request.setValue(JuncoVersion.userAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
      else { return nil }

      // Respect size limit
      let trimmedData = data.prefix(Self.maxBytes)
      guard let rawText = String(data: trimmedData, encoding: .utf8) else { return nil }

      let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
      let (title, content): (String?, String)

      if contentType.contains("json") {
        title = nil
        content = extractJSON(rawText)
      } else if contentType.contains("html") {
        title = extractTitle(from: rawText)
        content = stripHTML(rawText)
      } else {
        title = nil
        content = rawText
      }

      let truncated = TokenBudget.truncate(content, toTokens: maxTokens)

      return FetchedURL(
        url: url.absoluteString,
        title: title,
        content: truncated,
        bytesFetched: trimmedData.count
      )
    } catch {
      return nil
    }
  }

  /// Fetch multiple URLs concurrently, within a total token budget.
  public func fetchAll(urls: [URL], totalBudget: Int = 800) async -> [FetchedURL] {
    let perURLBudget = max(200, totalBudget / max(1, urls.count))

    return await withTaskGroup(of: FetchedURL?.self) { group in
      for url in urls.prefix(3) {  // Max 3 URLs per query
        group.addTask {
          await self.fetch(url: url, maxTokens: perURLBudget)
        }
      }

      var results: [FetchedURL] = []
      for await result in group {
        if let r = result { results.append(r) }
      }
      return results
    }
  }

  /// Format fetched URLs for prompt injection.
  public func formatForPrompt(fetched: [FetchedURL], budget: Int = 800) -> String? {
    guard !fetched.isEmpty else { return nil }

    var output = "Referenced URLs:\n"
    var tokensUsed = TokenBudget.estimate(output)

    for f in fetched {
      let header = "[\(f.url)]\(f.title.map { " — \($0)" } ?? ""):\n"
      let headerTokens = TokenBudget.estimate(header)
      let contentTokens = TokenBudget.estimate(f.content)

      if tokensUsed + headerTokens + contentTokens > budget { break }

      output += header + f.content + "\n\n"
      tokensUsed += headerTokens + contentTokens
    }

    return output
  }

  // MARK: - HTML Processing

  /// Extract <title> from HTML.
  private func extractTitle(from html: String) -> String? {
    guard let titleMatch = html.firstMatch(of: /(?i)<title[^>]*>(.*?)<\/title>/) else {
      return nil
    }
    return String(titleMatch.1)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Strip HTML tags and extract readable text.
  private func stripHTML(_ html: String) -> String {
    var text = html

    // Remove script and style blocks entirely
    text = text.replacingOccurrences(
      of: "<script[^>]*>[\\s\\S]*?</script>",
      with: "", options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: "<style[^>]*>[\\s\\S]*?</style>",
      with: "", options: .regularExpression
    )

    // Convert common block elements to newlines
    for tag in ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "<br>", "<br/>", "<br />"] {
      text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }

    // Strip remaining tags
    text = text.replacingOccurrences(
      of: "<[^>]+>", with: "", options: .regularExpression
    )

    // Decode common HTML entities
    let entities: [(String, String)] = [
      ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
      ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
      ("&#x27;", "'"), ("&#x2F;", "/")
    ]
    for (entity, char) in entities {
      text = text.replacingOccurrences(of: entity, with: char)
    }

    // Collapse whitespace
    text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Extract readable content from JSON (e.g., GitHub API responses).
  private func extractJSON(_ json: String) -> String {
    // Try to extract common fields from API responses
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return json }

    var parts: [String] = []

    // GitHub issue/PR
    if let title = obj["title"] as? String { parts.append("Title: \(title)") }
    if let body = obj["body"] as? String { parts.append(body) }
    if let message = obj["message"] as? String { parts.append(message) }

    // Generic description
    if let desc = obj["description"] as? String { parts.append(desc) }

    // README content
    if let content = obj["content"] as? String,
       let decoded = Data(base64Encoded: content),
       let text = String(data: decoded, encoding: .utf8) {
      parts.append(text)
    }

    return parts.isEmpty ? json : parts.joined(separator: "\n\n")
  }
}
