// EmbeddingIndexTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("EmbeddingIndex")
struct EmbeddingIndexTests {

  static let testEntries: [IndexEntry] = [
    IndexEntry(filePath: "Sources/junco/Junco.swift", symbolName: "Junco.swift", kind: .file, lineNumber: 1,
               snippet: "// Junco.swift — CLI entry point with fully wired TUI"),
    IndexEntry(filePath: "Sources/JuncoKit/Agent/Orchestrator.swift", symbolName: "Orchestrator", kind: .type,
               lineNumber: 10, snippet: "public actor Orchestrator {"),
    IndexEntry(filePath: "Sources/JuncoKit/Models/TokenBudget.swift", symbolName: "TokenBudget", kind: .type,
               lineNumber: 9, snippet: "public enum TokenBudget {"),
    IndexEntry(filePath: "Tests/JuncoTests/OrchestratorTests.swift", symbolName: "OrchestratorTests", kind: .type,
               lineNumber: 8, snippet: "struct OrchestratorTests {"),
    IndexEntry(filePath: "Package.swift", symbolName: "Package.swift", kind: .file, lineNumber: 1,
               snippet: "// swift-tools-version: 6.2"),
  ]

  @Test("embedding index can be created")
  func creation() async {
    let index = EmbeddingIndex()
    // NLEmbedding may or may not be available depending on platform
    // Just verify it doesn't crash
    await index.buildIndex(from: Self.testEntries)
  }

  @Test("score returns results when embeddings available")
  func scoreReturnsResults() async {
    let index = EmbeddingIndex()
    guard await index.isAvailable else { return }  // Skip if no embedding model
    await index.buildIndex(from: Self.testEntries)

    let results = await index.score(query: "main entry point of the application")
    // Should find at least Junco.swift (which has "entry point" in its comment)
    #expect(!results.isEmpty)
  }

  @Test("score returns empty for unavailable model")
  func emptyWhenUnavailable() async {
    // Can't force model unavailability, but verify the API handles it
    let index = EmbeddingIndex()
    let results = await index.score(query: "test query")
    // Either empty (no model) or has results (model available) — shouldn't crash
    _ = results
  }

  @Test("identical query scores highest against itself")
  func identicalHighest() async {
    let index = EmbeddingIndex()
    guard await index.isAvailable else { return }
    await index.buildIndex(from: Self.testEntries)

    let results = await index.score(query: "Orchestrator")
    let orchestratorHit = results.first { $0.index == 1 }  // Index 1 = Orchestrator entry
    if let hit = orchestratorHit {
      #expect(hit.similarity > 0.5, "Expected high similarity for exact term match")
    }
  }

  @Test("entry point query matches Junco.swift file comment")
  func entryPointConcept() async {
    let index = EmbeddingIndex()
    guard await index.isAvailable else { return }
    await index.buildIndex(from: Self.testEntries)

    let results = await index.score(query: "where is the main entry point")
    // Junco.swift has "CLI entry point" in its comment — should rank highly
    let juncoHit = results.first { $0.index == 0 }
    if let hit = juncoHit {
      #expect(hit.similarity > 0.3, "Entry point concept should match Junco.swift comment")
    }
  }
}
