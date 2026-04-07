// WebResearch.swift — Research Mode for the agent pipeline
//
// Triggered automatically when the query contains URLs or when the agent
// needs external context for disambiguation. Searches the web and fetches
// pages, then aggressively compacts results to fit within the 4K context.
//
// All on-device via URLSession — no browser, no API keys needed.

import Foundation

/// Compacted research context ready for prompt injection.
public struct ResearchContext: Sendable {
  /// Formatted text, already within the token budget.
  public let text: String
  /// Number of sources consulted (searches + fetches).
  public let sourceCount: Int
  /// Estimated tokens used.
  public let tokens: Int

  public var isEmpty: Bool { text.isEmpty }
}

/// Gathers external context from web search and URL fetching,
/// auto-compacting results to fit the small context window.
public struct WebResearch: Sendable {
  private let search: WebSearch
  private let fetcher: URLFetcher

  public init() {
    self.search = WebSearch()
    self.fetcher = URLFetcher()
  }

  // MARK: - Research Triggers

  /// Check if a query contains URLs that should be fetched for context.
  public func hasURLs(in query: String) -> Bool {
    !fetcher.extractURLs(from: query).isEmpty
  }

  /// Check if a query likely needs web research for disambiguation.
  /// Heuristic: short queries with no file targets and no clear action verb.
  public func needsResearch(query: String, intent: String, targets: [String]) -> Bool {
    // Queries referencing external APIs/frameworks not in the project
    let externalHints = [
      "how to", "how do i", "what is", "documentation for",
      "example of", "tutorial", "api for", "library for"
    ]
    let lower = query.lowercased()
    if externalHints.contains(where: { lower.contains($0) }) {
      return true
    }

    // Ambiguous queries with no targets
    if targets.isEmpty && query.count < 40 && intent == "explore" {
      return true
    }

    return false
  }

  // MARK: - Research Execution

  /// Fetch URLs found in the query and return compacted context.
  public func fetchURLContext(
    from query: String,
    budget: Int = 400
  ) async -> ResearchContext {
    let urls = fetcher.extractURLs(from: query)
    guard !urls.isEmpty else {
      return ResearchContext(text: "", sourceCount: 0, tokens: 0)
    }

    let fetched = await fetcher.fetchAll(urls: urls, totalBudget: budget)
    guard !fetched.isEmpty else {
      return ResearchContext(text: "", sourceCount: 0, tokens: 0)
    }

    let compacted = compact(fetched: fetched, budget: budget)
    return ResearchContext(
      text: compacted,
      sourceCount: fetched.count,
      tokens: TokenBudget.estimate(compacted)
    )
  }

  /// Search the web for a query and return compacted context.
  public func searchContext(
    query: String,
    budget: Int = 300
  ) async -> ResearchContext {
    guard let result = await search.search(query: query, maxResults: 3) else {
      return ResearchContext(text: "", sourceCount: 0, tokens: 0)
    }

    var text = ""
    if let answer = result.answer, !answer.isEmpty {
      text += "Search result: \(compactText(answer, budget: budget / 2))\n"
    }
    for topic in result.relatedTopics.prefix(2) {
      text += "- \(compactText(topic, budget: 80))\n"
    }

    let truncated = TokenBudget.truncate(text, toTokens: budget)
    return ResearchContext(
      text: truncated,
      sourceCount: 1,
      tokens: TokenBudget.estimate(truncated)
    )
  }

  /// Combined research: fetch any URLs in the query, then search if needed.
  /// Returns compacted context within the given token budget.
  public func research(
    query: String,
    budget: Int = 400
  ) async -> ResearchContext {
    // Phase 1: Fetch explicit URLs (higher priority — user provided them)
    let urlContext = await fetchURLContext(from: query, budget: budget)
    let remainingBudget = budget - urlContext.tokens

    // Phase 2: Search if there's budget left and no URL context was found
    if urlContext.isEmpty && remainingBudget > 100 {
      return await searchContext(query: query, budget: remainingBudget)
    }

    // Phase 3: If URLs were fetched, optionally search for more context
    if !urlContext.isEmpty && remainingBudget > 150 {
      let searchCtx = await searchContext(query: query, budget: remainingBudget)
      if !searchCtx.isEmpty {
        let combined = urlContext.text + "\n" + searchCtx.text
        let truncated = TokenBudget.truncate(combined, toTokens: budget)
        return ResearchContext(
          text: truncated,
          sourceCount: urlContext.sourceCount + searchCtx.sourceCount,
          tokens: TokenBudget.estimate(truncated)
        )
      }
    }

    return urlContext
  }

  // MARK: - Compaction

  /// Compact fetched URL content for prompt injection.
  /// Strips boilerplate, collapses whitespace, and truncates aggressively.
  private func compact(fetched: [FetchedURL], budget: Int) -> String {
    let perSource = max(100, budget / max(1, fetched.count))
    var output = ""
    var used = 0

    for f in fetched {
      let header = "[\(shortenURL(f.url))]"
      let titleLine = f.title.map { " \($0)" } ?? ""
      let prefix = "\(header)\(titleLine):\n"
      let prefixTokens = TokenBudget.estimate(prefix)

      let contentBudget = perSource - prefixTokens
      guard contentBudget > 30 else { continue }

      let compacted = compactText(f.content, budget: contentBudget)
      let section = prefix + compacted + "\n\n"
      let sectionTokens = TokenBudget.estimate(section)

      if used + sectionTokens > budget { break }
      output += section
      used += sectionTokens
    }

    return output
  }

  /// Aggressively compact text: strip navigation/boilerplate, collapse whitespace,
  /// keep only substantive content.
  private func compactText(_ text: String, budget: Int) -> String {
    var s = text

    // Remove common web boilerplate lines
    let boilerplate = [
      "skip to content", "skip to main", "sign in", "sign up", "log in",
      "cookie", "accept all", "privacy policy", "terms of service",
      "subscribe", "newsletter", "follow us", "share this",
      "advertisement", "sponsored", "loading..."
    ]
    s = s.components(separatedBy: "\n")
      .filter { line in
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.count > 3 && !boilerplate.contains(where: { lower.hasPrefix($0) })
      }
      .joined(separator: "\n")

    // Collapse runs of whitespace
    s = s.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)

    return TokenBudget.truncate(s, toTokens: budget)
  }

  /// Shorten a URL for display: strip scheme, www, trailing slash.
  private func shortenURL(_ url: String) -> String {
    var s = url
    s = s.replacingOccurrences(of: "https://", with: "")
    s = s.replacingOccurrences(of: "http://", with: "")
    s = s.replacingOccurrences(of: "www.", with: "")
    if s.hasSuffix("/") { s = String(s.dropLast()) }
    // Truncate very long URLs
    if s.count > 60 { s = String(s.prefix(57)) + "..." }
    return s
  }
}
