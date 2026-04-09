// ContextQualityTests.swift — Verify compression preserves critical information

import Testing
import Foundation
@testable import JuncoKit

@Suite("ContextQuality")
struct ContextQualityTests {
  let compressor = ProgressiveCompressor()

  // Sample Orchestrator-like code for compression testing
  let orchestratorCode = """
    import Foundation
    import FoundationModels

    /// Main agent pipeline orchestrator.
    public actor Orchestrator {
      private let adapter: AFMAdapter
      private let shell: SafeShell
      private let files: FileTools

      public func run(query: String) async throws -> RunResult {
        let intent = try await classify(query: query)
        let strategy = deterministicStrategy(intent: intent)
        let plan = try await plan(query: query, intent: intent, strategy: strategy)
        for step in plan.steps {
          try await executeStep(step: step)
        }
        return try await reflect()
      }

      private func classify(query: String) async throws -> AgentIntent {
        // ML classifier + LLM fallback
        return AgentIntent(domain: "swift", taskType: "fix", complexity: "simple", mode: "build", targets: [])
      }

      private func runSearch(query: String) async throws -> RunResult {
        // Deterministic multi-signal search
        let terms = extractSearchTerms(query)
        let hits = searchIndex(terms: terms)
        return formatResults(hits)
      }

      private func runPlan(query: String) async throws -> RunResult {
        // Structured plan generation
        return RunResult()
      }

      private func executeStep(step: PlanStep) async throws {
        // Tool dispatch
      }
    }
    """

  @Test("gist compression preserves key function names")
  func gistPreservesSymbols() {
    let gist = compressor.codeGist(orchestratorCode)
    #expect(gist.contains("run"), "Missing 'run' function")
    #expect(gist.contains("classify"), "Missing 'classify' function")
    #expect(gist.contains("runSearch"), "Missing 'runSearch' function")
    #expect(gist.contains("runPlan"), "Missing 'runPlan' function")
    #expect(gist.contains("executeStep"), "Missing 'executeStep' function")
  }

  @Test("gist compression preserves type declaration")
  func gistPreservesType() {
    let gist = compressor.codeGist(orchestratorCode)
    #expect(gist.contains("actor Orchestrator"), "Missing Orchestrator declaration")
  }

  @Test("gist compression preserves imports")
  func gistPreservesImports() {
    let gist = compressor.codeGist(orchestratorCode)
    #expect(gist.contains("import Foundation"))
    #expect(gist.contains("import FoundationModels"))
  }

  @Test("gist compression preserves properties")
  func gistPreservesProperties() {
    let gist = compressor.codeGist(orchestratorCode)
    #expect(gist.contains("adapter"))
    #expect(gist.contains("shell"))
    #expect(gist.contains("files"))
  }

  @Test("gist compression drops function body implementation")
  func gistDropsBodies() {
    let gist = compressor.codeGist(orchestratorCode)
    #expect(!gist.contains("ML classifier"), "Should not contain comment inside function body")
    #expect(!gist.contains("extractSearchTerms"), "Should not contain implementation detail")
  }

  @Test("micro compression of Orchestrator produces compact list")
  func microIsCompact() {
    let micro = compressor.codeMicro(orchestratorCode)
    #expect(micro.contains("Orchestrator"))
    #expect(micro.contains("run"))
    #expect(micro.contains("classify"))
    // Should be a single line (comma-separated)
    let lines = micro.components(separatedBy: "\n")
    #expect(lines.count <= 2, "Micro should be a compact single line, got \(lines.count) lines")
  }

  @Test("budget allocation never exceeds context window")
  func budgetNeverOverflows() {
    for stage in [ContextBudget.Stage.classify, .plan, .execute, .reflect] {
      let budget = ContextBudget.forWindow(4096, stage: stage)
      #expect(budget.total <= 4096, "Stage \(stage) budget \(budget.total) exceeds 4096")
    }
  }

  @Test("progressive compression at each tier reduces size")
  func tieredReduction() {
    let full = compressor.compress(code: orchestratorCode, target: 500)
    let gist = compressor.compress(code: orchestratorCode, target: 100)
    let micro = compressor.compress(code: orchestratorCode, target: 20)

    #expect(full.compressedTokens >= gist.compressedTokens)
    #expect(gist.compressedTokens >= micro.compressedTokens)
  }

  @Test("truncateSmart on code preserves declarations")
  func smartTruncateCode() {
    let result = TokenBudget.truncateSmart(orchestratorCode, toTokens: 70)
    // Should include the import and actor declaration (near the top)
    #expect(result.contains("import Foundation"))
    #expect(result.contains("actor Orchestrator"))
    // Should include some tail content too
    #expect(result.contains("omitted"))
  }
}

@Suite("SearchScoring")
struct SearchScoringTests {

  static let entries: [IndexEntry] = [
    IndexEntry(filePath: "Sources/Auth.swift", symbolName: "AuthService", kind: .type,
               lineNumber: 5, snippet: "public class AuthService {"),
    IndexEntry(filePath: "Sources/Auth.swift", symbolName: "login", kind: .function,
               lineNumber: 20, snippet: "func login(email: String, password: String) async throws"),
    IndexEntry(filePath: "Sources/Network.swift", symbolName: "NetworkClient", kind: .type,
               lineNumber: 3, snippet: "public struct NetworkClient: Sendable {"),
    IndexEntry(filePath: "Sources/Network.swift", symbolName: "request", kind: .function,
               lineNumber: 30, snippet: "func request(_ url: URL) async throws -> Data"),
    IndexEntry(filePath: "Tests/AuthTests.swift", symbolName: "AuthTests", kind: .type,
               lineNumber: 8, snippet: "struct AuthTests {"),
    IndexEntry(filePath: "Sources/App.swift", symbolName: "App.swift", kind: .file,
               lineNumber: 1, snippet: "// App.swift — main application")
  ]

  let index = SymbolIndex(entries: entries)

  @Test("exact symbol name match scores highest")
  func exactNameHighest() {
    let results = index.search(terms: ["AuthService"])
    #expect(results.first?.entry.symbolName == "AuthService")
    // Exact name match = 10 + type boost 2 = 12
    #expect(results.first?.score ?? 0 >= 10.0)
  }

  @Test("declaration type scores higher than function")
  func typeOverFunction() {
    let authResults = index.search(terms: ["Auth"])
    // AuthService (type) should score higher than login (function in same file)
    let typeHit = authResults.first { $0.entry.kind == .type }
    let funcHit = authResults.first { $0.entry.kind == .function }
    if let t = typeHit, let f = funcHit {
      #expect(t.score >= f.score, "Type should score >= function")
    }
  }

  @Test("multi-term search produces results")
  func multiTermSearch() {
    let results = index.search(terms: ["Auth", "login"])
    #expect(!results.isEmpty)
    // Both terms should find entries in Auth.swift
    #expect(results.contains { $0.entry.filePath == "Sources/Auth.swift" })
  }

  @Test("file-level entries score low unless name-matched")
  func fileLevelLowScore() {
    let results = index.search(terms: ["application"])
    // "App.swift" file entry matched by word "application" in snippet
    let fileHit = results.first { $0.entry.kind == .file }
    let typeHit = results.first { $0.entry.kind == .type }
    if let f = fileHit, let t = typeHit {
      #expect(f.score < t.score, "File-level should score lower than type")
    }
  }

  @Test("empty terms returns empty results")
  func emptyTerms() {
    let results = index.search(terms: [])
    #expect(results.isEmpty)
  }

  @Test("search is deterministic")
  func deterministic() {
    let r1 = index.search(terms: ["NetworkClient", "request"])
    let r2 = index.search(terms: ["NetworkClient", "request"])
    #expect(r1.count == r2.count)
    for (a, b) in zip(r1, r2) {
      #expect(a.entry.symbolName == b.entry.symbolName)
      #expect(a.score == b.score)
    }
  }
}
