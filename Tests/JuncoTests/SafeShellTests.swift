// SafeShellTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("SafeShell")
struct SafeShellTests {
  @Test("executes simple command")
  func simpleCommand() async throws {
    let shell = SafeShell(workingDirectory: "/tmp")
    let result = try await shell.execute("echo hello")
    #expect(result.stdout.contains("hello"))
    #expect(result.exitCode == 0)
  }

  @Test("captures stderr")
  func stderrCapture() async throws {
    let shell = SafeShell(workingDirectory: "/tmp")
    let result = try await shell.execute("echo err >&2")
    #expect(result.stderr.contains("err"))
  }

  @Test("blocks dangerous commands")
  func blockedCommands() async {
    let shell = SafeShell(workingDirectory: "/tmp")
    await #expect(throws: ShellError.self) { try await shell.execute("rm -rf /") }
    await #expect(throws: ShellError.self) { try await shell.execute("sudo ls") }
    await #expect(throws: ShellError.self) { try await shell.execute("shutdown now") }
  }

  @Test("formatted output includes exit code on failure")
  func formattedOutput() async throws {
    let shell = SafeShell(workingDirectory: "/tmp")
    let result = try await shell.execute("exit 1")
    let formatted = result.formatted()
    #expect(formatted.contains("exit code: 1"))
  }

  @Test("respects working directory")
  func workingDir() async throws {
    let dir = NSTemporaryDirectory() + "junco-sh-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    try "test".write(toFile: "\(dir)/marker.txt", atomically: true, encoding: .utf8)
    let shell = SafeShell(workingDirectory: dir)
    let result = try await shell.execute("ls marker.txt")
    #expect(result.stdout.contains("marker.txt"))
  }
}
