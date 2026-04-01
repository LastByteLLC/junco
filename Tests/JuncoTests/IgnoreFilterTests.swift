// IgnoreFilterTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("IgnoreFilter")
struct IgnoreFilterTests {
  @Test("ignores builtin directories")
  func builtinIgnores() {
    let filter = IgnoreFilter(workingDirectory: "/tmp")
    #expect(filter.shouldIgnore(".build/debug/main"))
    #expect(filter.shouldIgnore(".git/objects/abc"))
    #expect(filter.shouldIgnore(".junco/reflections.jsonl"))
    #expect(filter.shouldIgnore("DerivedData/Build/output"))
  }

  @Test("does not ignore normal files")
  func normalFiles() {
    let filter = IgnoreFilter(workingDirectory: "/tmp")
    #expect(!filter.shouldIgnore("Sources/main.swift"))
    #expect(!filter.shouldIgnore("README.md"))
    #expect(!filter.shouldIgnore("Package.swift"))
  }

  @Test("loads custom patterns from .juncoignore")
  func customPatterns() throws {
    let dir = NSTemporaryDirectory() + "junco-ign-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    try "*.log\nsecret/\n# comment\n".write(
      toFile: "\(dir)/.juncoignore", atomically: true, encoding: .utf8
    )

    let filter = IgnoreFilter(workingDirectory: dir)
    #expect(filter.shouldIgnore("app.log"))
    #expect(filter.shouldIgnore("secret/keys.txt"))
    #expect(!filter.shouldIgnore("main.swift"))
  }

  @Test("handles glob extension patterns")
  func globPatterns() throws {
    let dir = NSTemporaryDirectory() + "junco-ign2-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    try "*.sqlite\n*.tmp\n".write(
      toFile: "\(dir)/.juncoignore", atomically: true, encoding: .utf8
    )

    let filter = IgnoreFilter(workingDirectory: dir)
    #expect(filter.shouldIgnore("data.sqlite"))
    #expect(filter.shouldIgnore("cache.tmp"))
    #expect(!filter.shouldIgnore("data.json"))
  }
}
