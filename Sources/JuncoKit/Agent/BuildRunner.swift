// BuildRunner.swift — Post-edit build verification and test runner
//
// After the agent modifies files, automatically runs the project's
// build and test commands. Feeds failures back into working memory
// for potential self-correction.

import Foundation

/// Result of a build or test run.
public struct BuildResult: Sendable {
  public let command: String
  public let succeeded: Bool
  public let output: String
  public let duration: TimeInterval
}

/// Runs build and test commands after agent edits.
public struct BuildRunner: Sendable {
  private let shell: SafeShell
  private let domain: DomainConfig

  public init(workingDirectory: String, domain: DomainConfig) {
    self.shell = SafeShell(workingDirectory: workingDirectory)
    self.domain = domain
  }

  /// Run the domain's build command. Returns nil if no build command configured.
  public func build() async -> BuildResult? {
    guard let cmd = domain.buildCommand else { return nil }
    return await run(cmd)
  }

  /// Run the domain's test command. Returns nil if no test command configured.
  public func test() async -> BuildResult? {
    guard let cmd = domain.testCommand else { return nil }
    return await run(cmd)
  }

  /// Run the domain's lint command. Returns nil if no lint command configured.
  public func lint() async -> BuildResult? {
    guard let cmd = domain.lintCommand else { return nil }
    return await run(cmd)
  }

  /// Run a command and capture the result.
  private func run(_ command: String) async -> BuildResult {
    let start = Date()
    do {
      let result = try await shell.execute(command, timeout: 120)
      let duration = Date().timeIntervalSince(start)
      return BuildResult(
        command: command,
        succeeded: result.exitCode == 0,
        output: result.formatted(maxTokens: Config.toolOutputMaxTokens),
        duration: duration
      )
    } catch {
      let duration = Date().timeIntervalSince(start)
      return BuildResult(
        command: command,
        succeeded: false,
        output: "ERROR: \(error)",
        duration: duration
      )
    }
  }

  /// Run build verification after edits. Returns a summary for display.
  public func verify() async -> String {
    var results: [String] = []

    if let buildResult = await build() {
      let icon = buildResult.succeeded ? "ok" : "FAIL"
      results.append("[\(icon)] build (\(String(format: "%.1fs", buildResult.duration)))")
      if !buildResult.succeeded {
        results.append("  \(buildResult.output.prefix(200))")
      }
    }

    if let lintResult = await lint() {
      let icon = lintResult.succeeded ? "ok" : "warn"
      results.append("[\(icon)] lint (\(String(format: "%.1fs", lintResult.duration)))")
    }

    return results.isEmpty ? "" : results.joined(separator: "\n")
  }

  /// Format build errors for injection into working memory.
  public func errorsForMemory() async -> String? {
    guard let result = await build(), !result.succeeded else { return nil }
    return TokenBudget.truncate(result.output, toTokens: 200)
  }
}
