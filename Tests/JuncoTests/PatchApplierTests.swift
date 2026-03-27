// PatchApplierTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("PatchApplier")
struct PatchApplierTests {
  private func makeTempDir(files: [String: String]) throws -> (String, PatchApplier) {
    let dir = NSTemporaryDirectory() + "junco-patch-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      try content.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
    }
    return (dir, PatchApplier(workingDirectory: dir))
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  @Test("applies a simple addition patch")
  func simpleAddition() throws {
    let original = "line 1\nline 2\nline 3\n"
    let (dir, applier) = try makeTempDir(files: ["test.txt": original])
    defer { cleanup(dir) }

    let patch = """
    --- a/test.txt
    +++ b/test.txt
    @@ -1,3 +1,4 @@
     line 1
    +line 1.5
     line 2
     line 3
    """

    try applier.apply(patch: patch, to: "test.txt")

    let result = try String(contentsOfFile: "\(dir)/test.txt", encoding: .utf8)
    #expect(result.contains("line 1.5"))
    #expect(result.contains("line 1"))
    #expect(result.contains("line 2"))
  }

  @Test("applies a removal patch")
  func simpleRemoval() throws {
    let original = "line 1\nline 2\nline 3\n"
    let (dir, applier) = try makeTempDir(files: ["test.txt": original])
    defer { cleanup(dir) }

    let patch = """
    --- a/test.txt
    +++ b/test.txt
    @@ -1,3 +1,2 @@
     line 1
    -line 2
     line 3
    """

    try applier.apply(patch: patch, to: "test.txt")

    let result = try String(contentsOfFile: "\(dir)/test.txt", encoding: .utf8)
    #expect(!result.contains("line 2"))
    #expect(result.contains("line 1"))
    #expect(result.contains("line 3"))
  }

  @Test("applies a replacement patch")
  func replacement() throws {
    let original = "let x = 1\nlet y = 2\nlet z = 3\n"
    let (dir, applier) = try makeTempDir(files: ["code.swift": original])
    defer { cleanup(dir) }

    let patch = """
    --- a/code.swift
    +++ b/code.swift
    @@ -1,3 +1,3 @@
     let x = 1
    -let y = 2
    +let y = 42
     let z = 3
    """

    try applier.apply(patch: patch, to: "code.swift")

    let result = try String(contentsOfFile: "\(dir)/code.swift", encoding: .utf8)
    #expect(result.contains("let y = 42"))
    #expect(!result.contains("let y = 2"))
  }

  @Test("throws on missing file")
  func missingFile() throws {
    let (dir, applier) = try makeTempDir(files: [:])
    defer { cleanup(dir) }
    #expect(throws: PatchError.self) {
      try applier.apply(patch: "--- a/nope\n+++ b/nope\n", to: "nope.txt")
    }
  }

  @Test("throws on invalid patch")
  func invalidPatch() throws {
    let (dir, applier) = try makeTempDir(files: ["test.txt": "content"])
    defer { cleanup(dir) }
    #expect(throws: PatchError.self) {
      try applier.apply(patch: "not a valid patch", to: "test.txt")
    }
  }
}
