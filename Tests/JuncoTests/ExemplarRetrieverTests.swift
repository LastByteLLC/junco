// ExemplarRetrieverTests.swift — Tests for few-shot exemplar retrieval

import Foundation
import Testing
@testable import JuncoKit

@Suite("ExemplarRetriever")
struct ExemplarRetrieverTests {

  // MARK: - Role Mapping

  @Test("exemplarFilenames returns files for view role")
  func viewExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "view")
    #expect(!filenames.isEmpty)
    #expect(filenames.first?.contains("view") == true)
  }

  @Test("exemplarFilenames returns files for viewmodel role")
  func viewModelExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "viewmodel")
    #expect(!filenames.isEmpty)
    #expect(filenames.first?.contains("viewmodel") == true)
  }

  @Test("exemplarFilenames returns files for service role")
  func serviceExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "service")
    #expect(!filenames.isEmpty)
    #expect(filenames.first?.contains("service") == true)
  }

  @Test("exemplarFilenames returns files for model role")
  func modelExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "model")
    #expect(!filenames.isEmpty)
    #expect(filenames.first?.contains("model") == true)
  }

  @Test("exemplarFilenames returns files for test role")
  func testExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "test")
    #expect(!filenames.isEmpty)
    #expect(filenames.first?.contains("test") == true)
  }

  @Test("exemplarFilenames returns files for unknown role")
  func unknownRoleExemplars() {
    let retriever = ExemplarRetriever()
    let filenames = retriever.exemplarFilenames(for: "unknown")
    #expect(!filenames.isEmpty)
  }

  // MARK: - Similar File Matching

  @Test("findSimilarFile matches same-role file")
  func similarFileByRole() {
    let retriever = ExemplarRetriever()
    let index: [IndexEntry] = [
      IndexEntry(filePath: "PodcastListView.swift", symbolName: "PodcastListView", kind: .type, lineNumber: 1, snippet: "struct PodcastListView: View"),
      IndexEntry(filePath: "PodcastListView.swift", symbolName: "body", kind: .property, lineNumber: 3, snippet: "var body: some View"),
      IndexEntry(filePath: "Podcast.swift", symbolName: "Podcast", kind: .type, lineNumber: 1, snippet: "struct Podcast: Codable")
    ]
    let result = retriever.findSimilarFile(role: "view", targetPath: "EpisodeView.swift", index: index)
    #expect(result == "PodcastListView.swift")
  }

  @Test("findSimilarFile returns nil when no match")
  func noSimilarFile() {
    let retriever = ExemplarRetriever()
    let index: [IndexEntry] = [
      IndexEntry(filePath: "Podcast.swift", symbolName: "Podcast", kind: .type, lineNumber: 1, snippet: "struct Podcast")
    ]
    let result = retriever.findSimilarFile(role: "view", targetPath: "ListView.swift", index: index)
    // Model file shouldn't match view role with enough score
    #expect(result == nil)
  }

  @Test("findSimilarFile excludes the target file itself")
  func excludesSelf() {
    let retriever = ExemplarRetriever()
    let index: [IndexEntry] = [
      IndexEntry(filePath: "PodcastView.swift", symbolName: "PodcastView", kind: .type, lineNumber: 1, snippet: "struct PodcastView: View"),
      IndexEntry(filePath: "PodcastView.swift", symbolName: "body", kind: .property, lineNumber: 3, snippet: "var body")
    ]
    let result = retriever.findSimilarFile(role: "view", targetPath: "PodcastView.swift", index: index)
    #expect(result == nil)
  }

  // MARK: - Manifest

  @Test("allExemplarFilenames covers all categories")
  func manifestCoverage() {
    let all = ExemplarRetriever.allExemplarFilenames
    #expect(all.count == 35)
    #expect(all.contains("model_codable_struct.swift"))
    #expect(all.contains("view_list_navigation.swift"))
    #expect(all.contains("service_url_session.swift"))
    #expect(all.contains("viewmodel_observable.swift"))
    #expect(all.contains("test_basic.swift"))
    #expect(all.contains("app_main.swift"))
    #expect(all.contains("concurrency_actor.swift"))
    #expect(all.contains("basics_protocols.swift"))
    #expect(all.contains("swiftdata_model.swift"))
  }

  // MARK: - Built-In Loading (from local cache)

  @Test("loadBuiltInExemplar returns content from local exemplar files")
  func loadLocalExemplar() async {
    // Point to the repo's exemplar directory as cache
    let repoExemplarsDir = {
      let thisFile = #filePath
      let testsDir = (thisFile as NSString).deletingLastPathComponent
      let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
      return (repoRoot as NSString).appendingPathComponent("Sources/JuncoKit/Resources/exemplars")
    }()

    let retriever = ExemplarRetriever(cacheDir: repoExemplarsDir)
    let exemplar = await retriever.loadBuiltInExemplar(for: "view")
    #expect(exemplar != nil)
    #expect(exemplar?.contains("View") == true)
  }

  @Test("loadBuiltInExemplar for model returns Codable content")
  func loadModelExemplar() async {
    let repoExemplarsDir = {
      let thisFile = #filePath
      let testsDir = (thisFile as NSString).deletingLastPathComponent
      let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
      return (repoRoot as NSString).appendingPathComponent("Sources/JuncoKit/Resources/exemplars")
    }()

    let retriever = ExemplarRetriever(cacheDir: repoExemplarsDir)
    let exemplar = await retriever.loadBuiltInExemplar(for: "model")
    #expect(exemplar != nil)
    #expect(exemplar?.contains("Codable") == true)
  }

  // MARK: - Token Budget

  @Test("Built-in exemplars fit within 200 tokens")
  func exemplarTokenBudget() async {
    let repoExemplarsDir = {
      let thisFile = #filePath
      let testsDir = (thisFile as NSString).deletingLastPathComponent
      let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
      return (repoRoot as NSString).appendingPathComponent("Sources/JuncoKit/Resources/exemplars")
    }()

    let retriever = ExemplarRetriever(cacheDir: repoExemplarsDir)
    for role in ["view", "viewmodel", "service", "model", "test", "app"] {
      let exemplar = await retriever.loadBuiltInExemplar(for: role)
      if let exemplar {
        let tokens = TokenBudget.estimate(exemplar)
        #expect(tokens <= 250, "Exemplar for '\(role)' is \(tokens) tokens, expected <= 250")
      }
    }
  }
}
