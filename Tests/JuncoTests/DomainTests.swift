// DomainTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("Domain")
struct DomainTests {
  private func makeTempDir(files: [String: String] = [:]) throws -> String {
    let dir = NSTemporaryDirectory() + "junco-dom-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, content) in files {
      try content.write(toFile: "\(dir)/\(name)", atomically: true, encoding: .utf8)
    }
    return dir
  }

  private func cleanup(_ dir: String) {
    try? FileManager.default.removeItem(atPath: dir)
  }

  @Test("detects Swift from Package.swift")
  func detectSwift() throws {
    let dir = try makeTempDir(files: ["Package.swift": "// swift-tools-version: 6.2"])
    defer { cleanup(dir) }
    let detector = DomainDetector(workingDirectory: dir)
    let config = detector.detect()
    #expect(config.kind == .swift)
  }

  @Test("falls back to general for empty project")
  func detectGeneral() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }
    let detector = DomainDetector(workingDirectory: dir)
    let config = detector.detect()
    #expect(config.kind == .general)
  }

  @Test("respects manual config override")
  func manualOverride() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    // Create manual override
    let juncoDir = "\(dir)/.junco"
    try FileManager.default.createDirectory(atPath: juncoDir, withIntermediateDirectories: true)
    let config = JuncoConfig(domain: .swift)
    let data = try JSONEncoder().encode(config)
    try data.write(to: URL(fileURLWithPath: "\(juncoDir)/config.json"))

    let detector = DomainDetector(workingDirectory: dir)
    let detected = detector.detect()
    #expect(detected.kind == .swift)  // Override wins
  }

  @Test("Swift domain has correct file extensions")
  func swiftExtensions() {
    #expect(Domains.swift.fileExtensions.contains("swift"))
    #expect(Domains.swift.buildCommand != nil)
  }
}
