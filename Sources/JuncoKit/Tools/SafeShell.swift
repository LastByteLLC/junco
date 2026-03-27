// SafeShell.swift — Sandboxed shell execution with safety checks and timeouts

import Foundation

/// Result of a shell command execution.
public struct ShellResult: Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32

  /// Formatted output suitable for LLM consumption, truncated to token budget.
  public func formatted(maxTokens: Int = 400) -> String {
    var output = stdout
    if !stderr.isEmpty {
      output += (output.isEmpty ? "" : "\n") + "STDERR: \(stderr)"
    }
    if exitCode != 0 {
      output += "\n[exit code: \(exitCode)]"
    }
    if output.isEmpty { return "(no output)" }
    return TokenBudget.truncate(output, toTokens: maxTokens)
  }
}

/// Errors from shell execution.
public enum ShellError: Error, Sendable, Equatable {
  case blockedCommand(String)
  case timeout(seconds: Int)
  case executionFailed(String)
}

/// Safe shell executor with dangerous command blocking and timeout support.
public struct SafeShell: Sendable {
  /// Uses consolidated Config for blocked patterns.

  public let workingDirectory: String
  public let defaultTimeout: TimeInterval

  public init(workingDirectory: String, defaultTimeout: TimeInterval = Config.bashTimeout) {
    self.workingDirectory = workingDirectory
    self.defaultTimeout = defaultTimeout
  }

  /// Execute a shell command with safety checks and timeout.
  public func execute(
    _ command: String,
    timeout: TimeInterval? = nil
  ) async throws -> ShellResult {
    // Safety check against consolidated blocklist
    let lowerCmd = command.lowercased()
    if let match = Config.blockedShellPatterns.first(where: { lowerCmd.contains($0) }) {
      throw ShellError.blockedCommand(match)
    }

    let effectiveTimeout = timeout ?? defaultTimeout
    let cwd = workingDirectory

    return try await Task.detached {
      let process = Process()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()

      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = ["-c", command]
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      process.currentDirectoryURL = URL(fileURLWithPath: cwd)

      try process.run()

      // Timeout via SIGINT
      let timer = DispatchSource.makeTimerSource()
      timer.schedule(deadline: .now() + effectiveTimeout)
      timer.setEventHandler {
        if process.isRunning { process.interrupt() }
      }
      timer.resume()

      // Read pipes before wait to avoid deadlock
      let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()

      timer.cancel()

      return ShellResult(
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus
      )
    }.value
  }
}
