// RAGTests.swift — Tests for file indexing and context packing

import Testing
import Foundation
@testable import JuncoKit

@Suite("RAG")
struct RAGTests {
  private func makeTempProject(files: [String: String]) throws -> String {
    let dir = NSTemporaryDirectory() + "junco-rag-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      let path = "\(dir)/\(name)"
      let parent = (path as NSString).deletingLastPathComponent
      try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
      try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    return dir
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  // MARK: - FileIndexer

  @Test("indexes Swift functions")
  func swiftFunctions() throws {
    let dir = try makeTempProject(files: [
      "main.swift": """
        func greet(name: String) -> String {
            return "Hello, " + name
        }

        public func farewell() {
            print("bye")
        }
        """,
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let entries = indexer.indexProject()

    let functions = entries.filter { $0.kind == .function }
    #expect(functions.count == 2)
    #expect(functions.contains { $0.symbolName == "greet" })
    #expect(functions.contains { $0.symbolName == "farewell" })
  }

  @Test("indexes Swift types")
  func swiftTypes() throws {
    let dir = try makeTempProject(files: [
      "model.swift": """
        struct User {
            let name: String
        }

        class AuthManager {
            func login() {}
        }

        enum Status { case active, inactive }
        """,
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let entries = indexer.indexProject()

    let types = entries.filter { $0.kind == .type }
    #expect(types.contains { $0.symbolName == "User" })
    #expect(types.contains { $0.symbolName == "AuthManager" })
    #expect(types.contains { $0.symbolName == "Status" })
  }

  @Test("indexes JavaScript functions")
  func jsFunctions() throws {
    let dir = try makeTempProject(files: [
      "app.js": """
        function handleClick(event) {
          console.log(event);
        }

        const fetchData = async (url) => {
          return fetch(url);
        }

        export class App {
          constructor() {}
        }
        """,
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let entries = indexer.indexProject()

    let functions = entries.filter { $0.kind == .function }
    #expect(functions.contains { $0.symbolName == "handleClick" })
    #expect(functions.contains { $0.symbolName == "fetchData" })

    let types = entries.filter { $0.kind == .type }
    #expect(types.contains { $0.symbolName == "App" })
  }

  @Test("includes file-level entries")
  func fileEntries() throws {
    let dir = try makeTempProject(files: [
      "a.swift": "// file a",
      "b.js": "// file b",
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let entries = indexer.indexProject()
    let fileEntries = entries.filter { $0.kind == .file }
    #expect(fileEntries.count == 2)
  }

  // MARK: - ContextPacker

  @Test("packs relevant code within budget")
  func packWithinBudget() throws {
    let dir = try makeTempProject(files: [
      "auth.swift": """
        func login(user: String, pass: String) -> Bool {
            return validate(user, pass)
        }

        func logout() { session = nil }
        """,
      "utils.swift": """
        func formatDate(_ date: Date) -> String {
            return date.description
        }
        """,
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let index = indexer.indexProject()
    let packer = ContextPacker(workingDirectory: dir)

    let result = packer.pack(query: "fix the login function", index: index, budget: 400)
    #expect(result.contains("login"))
    #expect(TokenBudget.estimate(result) <= 450) // Allow some overhead
  }

  @Test("prefers preferred files")
  func preferredFiles() throws {
    let dir = try makeTempProject(files: [
      "target.swift": "func target() {}",
      "other.swift": "func other() {}",
    ])
    defer { cleanup(dir) }

    let indexer = FileIndexer(workingDirectory: dir)
    let index = indexer.indexProject()
    let packer = ContextPacker(workingDirectory: dir)

    let result = packer.pack(
      query: "update function",
      index: index,
      budget: 200,
      preferredFiles: ["target.swift"]
    )
    #expect(result.contains("target"))
  }

  @Test("returns placeholder for empty results")
  func emptyResults() {
    let packer = ContextPacker(workingDirectory: "/nonexistent")
    let result = packer.pack(query: "anything", index: [], budget: 100)
    #expect(result.contains("no relevant code"))
  }
}
