// URLFetcherTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("URLFetcher")
struct URLFetcherTests {
  let fetcher = URLFetcher()

  @Test("extracts HTTPS URLs from text")
  func extractHTTPS() {
    let text = "check https://example.com/docs for details"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls.count == 1)
    #expect(urls[0].absoluteString == "https://example.com/docs")
  }

  @Test("upgrades HTTP to HTTPS")
  func upgradeHTTP() {
    let text = "see http://example.com/api"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls.count == 1)
    #expect(urls[0].scheme == "https")
  }

  @Test("extracts multiple URLs")
  func multipleURLs() {
    let text = "compare https://a.com and https://b.com/path"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls.count == 2)
  }

  @Test("trims trailing punctuation from URLs")
  func trailingPunctuation() {
    let text = "see https://example.com/page. Also https://other.com/doc,"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls[0].absoluteString == "https://example.com/page")
    #expect(urls[1].absoluteString == "https://other.com/doc")
  }

  @Test("separateURLs returns clean query and extracted URLs")
  func separateURLs() {
    let text = "fix the bug described at https://github.com/org/repo/issues/42"
    let (query, urls) = fetcher.separateURLs(from: text)
    #expect(query == "fix the bug described at")
    #expect(urls.count == 1)
    #expect(urls[0].absoluteString == "https://github.com/org/repo/issues/42")
  }

  @Test("handles text with no URLs")
  func noURLs() {
    let text = "fix the login bug in auth.swift"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls.isEmpty)
  }

  @Test("handles URLs with query parameters")
  func queryParams() {
    let text = "see https://example.com/search?q=swift&page=2"
    let urls = fetcher.extractURLs(from: text)
    #expect(urls.count == 1)
    #expect(urls[0].absoluteString.contains("q=swift"))
  }

  @Test("fetches real HTTPS URL")
  func fetchReal() async {
    let url = URL(string: "https://httpbin.org/robots.txt")!
    let result = await fetcher.fetch(url: url, maxTokens: 100)
    #expect(result != nil)
    #expect(result!.bytesFetched > 0)
  }

  @Test("formatForPrompt produces bounded output")
  func formatBudget() {
    let fetched = [
      FetchedURL(url: "https://example.com", title: "Example", content: "Some content here", bytesFetched: 100),
    ]
    let formatted = fetcher.formatForPrompt(fetched: fetched, budget: 200)
    #expect(formatted != nil)
    #expect(formatted!.contains("example.com"))
    #expect(TokenBudget.estimate(formatted!) <= 250)
  }
}
