// PlatformShell.swift — Cross-platform shell abstraction
//
// On macOS: delegates to SafeShell (real Process execution)
// On iOS: no-op that returns descriptive messages (Process unavailable)

import Foundation

/// Platform-agnostic shell execution.
public struct PlatformShell: Sendable {
  #if os(macOS)
  private let shell: SafeShell

  public init(workingDirectory: String) {
    self.shell = SafeShell(workingDirectory: workingDirectory)
  }

  public func execute(_ command: String, timeout: TimeInterval? = nil) async throws -> ShellResult {
    try await shell.execute(command, timeout: timeout)
  }
  #else
  public init(workingDirectory: String) {}

  public func execute(_ command: String, timeout: TimeInterval? = nil) async throws -> ShellResult {
    // iOS: shell execution not available
    ShellResult(
      stdout: "[iOS] Shell execution not available. Command: \(command)",
      stderr: "",
      exitCode: 0
    )
  }
  #endif
}
