// FileToolsTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("FileTools")
struct FileToolsTests {
  private func makeTempDir(files: [String: String] = [:]) throws -> (String, FileTools) {
    let dir = NSTemporaryDirectory() + "junco-ft-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      try content.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
    }
    return (dir, FileTools(workingDirectory: dir))
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  @Test("resolve rejects paths outside working directory")
  func pathContainment() throws {
    let (dir, ft) = try makeTempDir()
    defer { cleanup(dir) }
    #expect(throws: FileToolError.self) { try ft.resolve("../../etc/passwd") }
  }

  @Test("resolve handles relative paths")
  func relativePaths() throws {
    let (dir, ft) = try makeTempDir(files: ["test.swift": "code"])
    defer { cleanup(dir) }
    let resolved = try ft.resolve("test.swift")
    #expect(resolved.hasSuffix("test.swift"))
    #expect(resolved.hasPrefix(dir))
  }

  @Test("read returns file content")
  func readFile() throws {
    let (dir, ft) = try makeTempDir(files: ["a.swift": "let x = 1"])
    defer { cleanup(dir) }
    let content = try ft.read(path: "a.swift")
    #expect(content.contains("let x = 1"))
  }

  @Test("read throws for missing file")
  func readMissing() throws {
    let (dir, ft) = try makeTempDir()
    defer { cleanup(dir) }
    #expect(throws: FileToolError.self) { try ft.read(path: "nope.swift") }
  }

  @Test("write creates file with content")
  func writeFile() throws {
    let (dir, ft) = try makeTempDir()
    defer { cleanup(dir) }
    try ft.write(path: "new.swift", content: "let y = 2")
    let content = try ft.read(path: "new.swift")
    #expect(content.contains("let y = 2"))
  }

  @Test("write blocks sensitive files")
  func writeSensitive() throws {
    let (dir, ft) = try makeTempDir()
    defer { cleanup(dir) }
    #expect(throws: FileToolError.self) { try ft.write(path: ".env", content: "SECRET=x") }
    #expect(throws: FileToolError.self) { try ft.write(path: "credentials.json", content: "{}") }
  }

  @Test("edit performs find-replace")
  func editFile() throws {
    let (dir, ft) = try makeTempDir(files: ["a.swift": "let x = 1"])
    defer { cleanup(dir) }
    try ft.edit(path: "a.swift", find: "let x = 1", replace: "let x = 42")
    let content = try ft.read(path: "a.swift")
    #expect(content.contains("let x = 42"))
  }

  @Test("edit throws when text not found")
  func editNotFound() throws {
    let (dir, ft) = try makeTempDir(files: ["a.swift": "let x = 1"])
    defer { cleanup(dir) }
    #expect(throws: FileToolError.self) {
      try ft.edit(path: "a.swift", find: "nonexistent", replace: "new")
    }
  }

  @Test("edit fuzzy matches trimmed whitespace")
  func editFuzzy() throws {
    let (dir, ft) = try makeTempDir(files: ["a.swift": "  let x = 1  "])
    defer { cleanup(dir) }
    try ft.edit(path: "a.swift", find: "  let x = 1  \n", replace: "let x = 42", fuzzy: true)
    let content = try ft.read(path: "a.swift")
    #expect(content.contains("let x = 42"))
  }

  @Test("listFiles finds project files")
  func listFiles() throws {
    let (dir, ft) = try makeTempDir(files: [
      "a.swift": "", "b.swift": "", "c.txt": ""
    ])
    defer { cleanup(dir) }
    let list = ft.listFiles()
    #expect(list.contains("a.swift"))
    #expect(list.contains("b.swift"))
    #expect(!list.contains("c.txt"))  // .txt not in default extensions
  }

  @Test("exists checks file presence")
  func existsCheck() throws {
    let (dir, ft) = try makeTempDir(files: ["yes.swift": ""])
    defer { cleanup(dir) }
    #expect(ft.exists("yes.swift"))
    #expect(!ft.exists("no.swift"))
  }
}
