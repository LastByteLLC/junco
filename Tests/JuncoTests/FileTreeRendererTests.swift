// FileTreeRendererTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("FileTreeRenderer")
struct FileTreeRendererTests {
  private func makeTempProject(files: [String: String]) throws -> String {
    let dir = NSTemporaryDirectory() + "junco-tree-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      let path = "\(dir)/\(name)"
      let parent = (path as NSString).deletingLastPathComponent
      try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
      try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
    return dir
  }

  @Test("renders files with tree characters")
  func basicTree() throws {
    let dir = try makeTempProject(files: [
      "main.swift": "", "lib/util.swift": "", "lib/helper.swift": "",
    ])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let renderer = FileTreeRenderer(workingDirectory: dir)
    let output = renderer.render()

    #expect(output.contains("main.swift"))
    #expect(output.contains("lib/"))
    #expect(output.contains("util.swift"))
    #expect(output.contains("\u{251C}") || output.contains("\u{2514}"))  // Box drawing chars
  }

  @Test("directories sorted before files")
  func sortOrder() throws {
    let dir = try makeTempProject(files: [
      "z_file.swift": "", "a_dir/inner.swift": "",
    ])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let renderer = FileTreeRenderer(workingDirectory: dir)
    let output = renderer.render()
    let lines = output.components(separatedBy: "\n")

    let dirLine = lines.firstIndex { $0.contains("a_dir") } ?? Int.max
    let fileLine = lines.firstIndex { $0.contains("z_file") } ?? Int.max
    #expect(dirLine < fileLine)
  }

  @Test("respects maxDepth")
  func maxDepth() throws {
    let dir = try makeTempProject(files: [
      "a/b/c/d/deep.swift": "",
    ])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let renderer = FileTreeRenderer(workingDirectory: dir)
    let shallow = renderer.render(maxDepth: 2)
    #expect(!shallow.contains("deep.swift"))
  }

  @Test("summary produces compact output")
  func summary() throws {
    let dir = try makeTempProject(files: [
      "Sources/a.swift": "", "Sources/b.swift": "", "Tests/t.swift": "",
    ])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let renderer = FileTreeRenderer(workingDirectory: dir)
    let output = renderer.summary()
    #expect(output.contains("Sources/"))
    #expect(output.contains("Tests/"))
  }

  @Test("ignores .build directory")
  func ignoresBuild() throws {
    let dir = try makeTempProject(files: [
      "main.swift": "", ".build/debug/binary": "",
    ])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let renderer = FileTreeRenderer(workingDirectory: dir)
    let output = renderer.render()
    #expect(!output.contains(".build"))
    #expect(output.contains("main.swift"))
  }
}
