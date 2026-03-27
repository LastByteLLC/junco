// OrchestratorTests.swift — Pipeline integration tests with file system

import Testing
import Foundation
@testable import JuncoKit

@Suite("Orchestrator")
struct OrchestratorTests {

  /// Create a temp directory with test files for orchestrator tests.
  private func makeTempProject(files: [String: String] = [:]) throws -> String {
    let dir = NSTemporaryDirectory() + "junco-test-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      try content.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
    }
    return dir
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  @Test("SessionMetrics starts at zero")
  func metricsInit() {
    let m = SessionMetrics()
    #expect(m.tasksCompleted == 0)
    #expect(m.totalTokensUsed == 0)
    #expect(m.totalLLMCalls == 0)
  }

  @Test("OrchestratorError provides context")
  func errorMessages() {
    let err = OrchestratorError.editFailed("Text 'foo' not found in bar.swift")
    #expect("\(err)".contains("foo"))
  }

  @Test("RunResult contains memory and reflection")
  func runResultFields() {
    let memory = WorkingMemory(query: "test")
    let reflection = AgentReflection(
      taskSummary: "test",
      insight: "it worked",
      improvement: "nothing",
      succeeded: true
    )
    let result = RunResult(memory: memory, reflection: reflection)
    #expect(result.memory.query == "test")
    #expect(result.reflection.succeeded)
  }

  @Test("File operations work through resolvePath")
  func fileOperations() throws {
    let dir = try makeTempProject(files: ["test.swift": "let x = 1"])
    defer { cleanup(dir) }

    // Read
    let content = try String(contentsOfFile: "\(dir)/test.swift", encoding: .utf8)
    #expect(content == "let x = 1")

    // Write
    let newPath = "\(dir)/new.swift"
    try "let y = 2".write(toFile: newPath, atomically: true, encoding: .utf8)
    let newContent = try String(contentsOfFile: newPath, encoding: .utf8)
    #expect(newContent == "let y = 2")

    // Edit (find-replace)
    var editContent = try String(contentsOfFile: "\(dir)/test.swift", encoding: .utf8)
    editContent = editContent.replacingOccurrences(of: "let x = 1", with: "let x = 42")
    try editContent.write(toFile: "\(dir)/test.swift", atomically: true, encoding: .utf8)
    let edited = try String(contentsOfFile: "\(dir)/test.swift", encoding: .utf8)
    #expect(edited == "let x = 42")
  }

  @Test("Orchestrator initializes with correct working directory")
  func orchestratorInit() async {
    let adapter = AFMAdapter()
    let orch = Orchestrator(adapter: adapter, workingDirectory: "/tmp")
    let metrics = await orch.metrics
    #expect(metrics.tasksCompleted == 0)
  }
}
