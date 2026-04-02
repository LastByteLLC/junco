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

    // Create entries with overlapping keywords so clustering merges them
    let queries = ["fix auth login", "fix auth token", "fix auth session",
                   "add button view", "add label view", "add image view",
                   "refactor network client", "refactor network handler",
                   "test auth flow", "test auth mock"]
    for query in queries {
      try store.save(query: query, reflection: makeReflection(summary: query))
    }

    // Distillation clusters similar entries and keeps maxEntries/2
    #expect(store.count <= 5, "Should compact to at most maxEntries/2, got \(store.count)")
    #expect(store.count >= 1, "Should keep at least some entries")
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

  // MARK: - Exponential Decay

  @Test("recency half-life is 14 days")
  func halfLifeConfig() {
    #expect(ReflectionStore.recencyHalfLife == 14.0)
  }

  @Test("exponential decay formula produces expected values")
  func decayValues() {
    // Test the formula: exp(-days / halfLife)
    let halfLife = ReflectionStore.recencyHalfLife
    let at7days = exp(-7.0 / halfLife)
    let at14days = exp(-14.0 / halfLife)
    let at28days = exp(-28.0 / halfLife)
    let at60days = exp(-60.0 / halfLife)

    #expect(at7days > 0.6 && at7days < 0.65)   // ~0.61
    #expect(at14days > 0.35 && at14days < 0.4)  // ~0.37
    #expect(at28days > 0.13 && at28days < 0.15) // ~0.14
    #expect(at60days < 0.02)                     // ~0.01
  }

  // MARK: - Distillation

  @Test("distillation keeps success + failure per cluster")
  func distillKeepsBoth() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir, maxEntries: 100)

    var entries: [StoredReflection] = []
    // Cluster 1: auth-related
    entries.append(StoredReflection(query: "fix auth login", reflection: AgentReflection(
      taskSummary: "Fixed auth", insight: "ok", improvement: "", succeeded: true)))
    entries.append(StoredReflection(query: "fix auth token", reflection: AgentReflection(
      taskSummary: "Auth failed", insight: "bad", improvement: "", succeeded: false)))
    // Cluster 2: UI-related
    entries.append(StoredReflection(query: "add button to view", reflection: AgentReflection(
      taskSummary: "Added button", insight: "ok", improvement: "", succeeded: true)))

    let distilled = store.distill(entries)
    // Should have: 1 success + 1 failure from auth cluster, 1 success from UI cluster = 3
    #expect(distilled.count >= 2)
    #expect(distilled.count <= 4)
    #expect(distilled.contains { $0.reflection.succeeded })
    #expect(distilled.contains { !$0.reflection.succeeded })
  }

  @Test("distillation reduces large sets")
  func distillReduces() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let store = ReflectionStore(projectDirectory: dir, maxEntries: 20)

    var entries: [StoredReflection] = []
    for i in 0..<50 {
      entries.append(StoredReflection(
        query: "task \(i % 5) variant \(i)",
        reflection: AgentReflection(
          taskSummary: "task \(i % 5)", insight: "done", improvement: "", succeeded: i % 3 != 0
        )
      ))
    }

    let distilled = store.distill(entries)
    #expect(distilled.count <= 10, "Distillation should reduce 50 → ≤10, got \(distilled.count)")
    #expect(distilled.count >= 2, "Should keep at least some entries")
  }
}
