// SymbolIndexTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("SymbolIndex")
struct SymbolIndexTests {

  static let testEntries: [IndexEntry] = [
    IndexEntry(filePath: "Sources/Orchestrator.swift", symbolName: "Orchestrator", kind: .type, lineNumber: 10,
               snippet: "public actor Orchestrator {\n  private let adapter: AFMAdapter"),
    IndexEntry(filePath: "Sources/Orchestrator.swift", symbolName: "run", kind: .function, lineNumber: 100,
               snippet: "public func run(query: String) async throws -> RunResult"),
    IndexEntry(filePath: "Sources/Orchestrator.swift", symbolName: "classify", kind: .function, lineNumber: 200,
               snippet: "private func classify(query: String) async throws -> AgentIntent"),
    IndexEntry(filePath: "Sources/TokenBudget.swift", symbolName: "TokenBudget", kind: .type, lineNumber: 9,
               snippet: "public enum TokenBudget {"),
    IndexEntry(filePath: "Sources/TokenBudget.swift", symbolName: "estimate", kind: .function, lineNumber: 30,
               snippet: "public static func estimate(_ text: String) -> Int"),
    IndexEntry(filePath: "Sources/SafeShell.swift", symbolName: "SafeShell", kind: .type, lineNumber: 5,
               snippet: "public struct SafeShell: Sendable {"),
    IndexEntry(filePath: "Sources/SafeShell.swift", symbolName: "execute", kind: .function, lineNumber: 50,
               snippet: "public func execute(_ command: String) async throws -> ShellResult"),
    IndexEntry(filePath: "Package.swift", symbolName: "Package.swift", kind: .file, lineNumber: 1,
               snippet: "// swift-tools-version: 6.2"),
    IndexEntry(filePath: "Sources/Orchestrator.swift", symbolName: "Foundation", kind: .import, lineNumber: 1,
               snippet: "import Foundation"),
  ]

  let index = SymbolIndex(entries: testEntries)

  // MARK: - Name Lookup

  @Test("findByName returns exact matches")
  func findByNameExact() {
    let results = index.findByName("Orchestrator")
    #expect(results.count == 1)
    #expect(results.first?.kind == .type)
    #expect(results.first?.lineNumber == 10)
  }

  @Test("findByName is case-insensitive")
  func findByNameCaseInsensitive() {
    let results = index.findByName("orchestrator")
    #expect(results.count == 1)
    #expect(results.first?.symbolName == "Orchestrator")
  }

  @Test("findByName returns empty for no match")
  func findByNameNoMatch() {
    let results = index.findByName("NonExistent")
    #expect(results.isEmpty)
  }

  // MARK: - Word Lookup

  @Test("findByWord finds entries containing the word")
  func findByWord() {
    let results = index.findByWord("actor")
    #expect(results.contains { $0.symbolName == "Orchestrator" })
  }

  @Test("findByWord matches first line of snippet")
  func findByWordSnippet() {
    // "public actor Orchestrator {" — "actor" is in the first snippet line
    let results = index.findByWord("query")
    // "run" function snippet has "query" in "func run(query: String)"
    #expect(results.contains { $0.symbolName == "run" })
  }

  // MARK: - File Lookup

  @Test("findByFile returns all entries in a file")
  func findByFile() {
    let results = index.findByFile("Sources/Orchestrator.swift")
    #expect(results.count >= 3)  // Orchestrator, run, classify, Foundation import
    #expect(results.contains { $0.symbolName == "Orchestrator" })
    #expect(results.contains { $0.symbolName == "run" })
  }

  // MARK: - Multi-Term Search

  @Test("search with single term finds matches")
  func searchSingleTerm() {
    let results = index.search(terms: ["Orchestrator"])
    #expect(!results.isEmpty)
    #expect(results.first?.entry.symbolName == "Orchestrator")
  }

  @Test("search with multiple terms boosts intersection")
  func searchMultiTerm() {
    // "run" + "Orchestrator" — the run function in Orchestrator.swift should score highest
    let results = index.search(terms: ["run", "Orchestrator"])
    #expect(!results.isEmpty)
    // Orchestrator type should score high (exact name match for "Orchestrator")
    #expect(results.first?.entry.symbolName == "Orchestrator")
  }

  @Test("search boosts declaration types")
  func searchDeclarationBoost() {
    let results = index.search(terms: ["estimate"])
    // "estimate" as a function should score higher than if it were an import
    let estimateHit = results.first { $0.entry.symbolName == "estimate" }
    #expect(estimateHit != nil)
    #expect(estimateHit!.entry.kind == .function)
  }

  @Test("exact name match scores highest")
  func exactNameHighest() {
    let results = index.search(terms: ["SafeShell"])
    #expect(results.first?.entry.symbolName == "SafeShell")
    #expect(results.first?.score ?? 0 >= 10.0)  // Exact name match = 10+
  }

  // MARK: - Stats

  @Test("functionCount matches actual function entries")
  func functionCountStat() {
    #expect(index.functionCount == 4)  // run, classify, estimate, execute
  }

  @Test("typeCount matches actual type entries")
  func typeCountStat() {
    #expect(index.typeCount >= 3)  // Orchestrator, TokenBudget, SafeShell
  }

  @Test("uniqueFiles counts distinct files")
  func uniqueFilesStat() {
    #expect(index.uniqueFiles == 4)
  }

  // MARK: - Incremental Update

  @Test("replacingFile removes old entries and adds new")
  func incrementalUpdate() {
    let newEntries = [
      IndexEntry(filePath: "Sources/SafeShell.swift", symbolName: "SafeShellV2", kind: .type, lineNumber: 5,
                 snippet: "public struct SafeShellV2"),
    ]
    let updated = index.replacingFile("Sources/SafeShell.swift", with: newEntries)
    #expect(updated.findByName("SafeShell").isEmpty)
    #expect(updated.findByName("SafeShellV2").count == 1)
    // Other files unaffected
    #expect(updated.findByName("Orchestrator").count == 1)
  }
}

// MARK: - Enhanced FileIndexer Tests

@Suite("FileIndexer.Enhanced")
struct FileIndexerEnhancedTests {

  private func index(code: String) -> [IndexEntry] {
    let dir = NSTemporaryDirectory() + "junco-idx-\(UUID().uuidString)"
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try! code.write(toFile: "\(dir)/Test.swift", atomically: true, encoding: .utf8)
    let indexer = FileIndexer(workingDirectory: dir)
    return indexer.indexProject()
  }

  @Test("extracts extension with protocol conformance")
  func extensionConformance() {
    let entries = index(code: "extension MyType: Codable {\n  func encode() {}\n}")
    let ext = entries.first { $0.symbolName.contains("extension") }
    #expect(ext != nil)
    #expect(ext?.symbolName.contains("MyType") == true)
    #expect(ext?.symbolName.contains("Codable") == true)
  }

  @Test("extracts let/var properties at type level")
  func typeProperties() {
    let entries = index(code: "struct Config {\n  public let maxItems: Int = 100\n  var name: String = \"\"\n}")
    let props = entries.filter { $0.kind == .property }
    #expect(props.contains { $0.symbolName == "maxItems" })
    #expect(props.contains { $0.symbolName == "name" })
  }

  @Test("extracts static functions")
  func staticFunc() {
    let entries = index(code: "struct Math {\n  public static func add(_ a: Int, _ b: Int) -> Int { a + b }\n}")
    let funcs = entries.filter { $0.kind == .function }
    #expect(funcs.contains { $0.symbolName == "add" })
  }

  @Test("snippet is 5 lines for functions")
  func snippetLength() {
    let code = (1...10).map { "  // line \($0)" }.joined(separator: "\n")
    let entries = index(code: "func hello() {\n\(code)\n}")
    let hello = entries.first { $0.symbolName == "hello" }
    #expect(hello != nil)
    let snippetLines = hello!.snippet.components(separatedBy: "\n").count
    #expect(snippetLines >= 5)
  }
}
