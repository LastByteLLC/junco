// ReflectionStoreTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("ReflectionStore")
struct ReflectionStoreTests {
  private func makeTempDir() throws -> String {
    let dir = NSTemporaryDirectory() + "junco-ref-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  private func makeReflection(
    summary: String = "test", insight: String = "it worked",
    improvement: String = "nothing", succeeded: Bool = true
  ) -> AgentReflection {
    AgentReflection(
      taskSummary: summary, insight: insight,
      improvement: improvement, succeeded: succeeded
    )
  }

  @Test("saves and retrieves reflections")
  func saveAndRetrieve() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir)

    try store.save(query: "fix login bug", reflection: makeReflection(
      summary: "Fixed login", insight: "Token was expired", improvement: "Check token first"
    ))
    try store.save(query: "add search feature", reflection: makeReflection(
      summary: "Added search", insight: "Used grep", improvement: "Index files first"
    ))

    #expect(store.count == 2)

    let results = store.retrieve(query: "login authentication token", limit: 2)
    #expect(!results.isEmpty)
    #expect(results[0].reflection.taskSummary == "Fixed login")
  }

  @Test("formats reflections for prompt")
  func formatForPrompt() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir)

    try store.save(query: "fix auth", reflection: makeReflection(
      insight: "Session expired", improvement: "Refresh token"
    ))

    let formatted = store.formatForPrompt(query: "auth problem")
    #expect(formatted != nil)
    #expect(formatted!.contains("Session expired"))
    #expect(formatted!.contains("Refresh token"))
  }

  @Test("returns nil when no reflections match")
  func noMatch() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir)

    let formatted = store.formatForPrompt(query: "xyz")
    #expect(formatted == nil)
  }

  @Test("auto-compacts when exceeding max entries")
  func autoCompact() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir, maxEntries: 5)

    for i in 0..<10 {
      try store.save(query: "task \(i)", reflection: makeReflection(summary: "task \(i)"))
    }

    #expect(store.count == 5)
  }

  @Test("persists across store instances")
  func persistence() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let store1 = ReflectionStore(projectDirectory: dir)
    try store1.save(query: "test", reflection: makeReflection(summary: "persisted"))

    let store2 = ReflectionStore(projectDirectory: dir)
    #expect(store2.count == 1)
    let results = store2.retrieve(query: "test")
    #expect(results[0].reflection.taskSummary == "persisted")
  }
}
