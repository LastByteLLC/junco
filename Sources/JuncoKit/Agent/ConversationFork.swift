// ConversationFork.swift — Branch conversations to try different approaches
//
// When the user says "try a different approach" or uses /fork,
// snapshots the current state (git stash) and starts a new branch
// of the conversation. /unfork restores the original state.
//
// Forks are stored as a stack — you can fork from a fork.

import Foundation

/// A saved fork point in the conversation.
public struct ForkPoint: Codable, Sendable {
  public let id: String
  public let query: String
  public let timestamp: Date
  public let gitStashRef: String?
  public let turnIndex: Int

  public init(query: String, turnIndex: Int, gitStashRef: String? = nil) {
    self.id = UUID().uuidString.prefix(6).lowercased().description
    self.query = String(query.prefix(80))
    self.timestamp = Date()
    self.gitStashRef = gitStashRef
    self.turnIndex = turnIndex
  }
}

/// Manages conversation forking and restoration.
public actor ConversationForker {
  private let shell: SafeShell
  private let workingDirectory: String
  private var forkStack: [ForkPoint] = []

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
    self.shell = SafeShell(workingDirectory: workingDirectory)
  }

  /// Create a fork point — snapshots current file state.
  public func fork(query: String, turnIndex: Int) async -> ForkPoint {
    // Try to stash current changes
    var stashRef: String?

    if await isGitRepo() {
      let stashName = "junco-fork-\(Int(Date().timeIntervalSince1970))"
      // Create a stash including untracked files
      let result = try? await shell.execute(
        "git stash push -m '\(stashName)' --include-untracked 2>/dev/null"
      )
      if let r = result, r.stdout.contains("Saved") {
        stashRef = stashName
        // Pop immediately — we keep the stash entry but continue working
        _ = try? await shell.execute("git stash pop --quiet 2>/dev/null")
      }
    }

    let point = ForkPoint(query: query, turnIndex: turnIndex, gitStashRef: stashRef)
    forkStack.append(point)
    return point
  }

  /// Restore to the most recent fork point.
  /// Returns the fork point if successful, nil if no forks exist.
  public func unfork() async -> ForkPoint? {
    guard let point = forkStack.popLast() else { return nil }

    if await isGitRepo() {
      // Discard all changes since the fork
      _ = try? await shell.execute("git checkout -- . 2>/dev/null")
      _ = try? await shell.execute("git clean -fd 2>/dev/null")

      // If we have a stash ref, apply it to restore the exact fork state
      if let stashRef = point.gitStashRef {
        let list = try? await shell.execute("git stash list 2>/dev/null")
        if let output = list?.stdout, output.contains(stashRef) {
          // Find the stash index
          let lines = output.components(separatedBy: "\n")
          if let idx = lines.firstIndex(where: { $0.contains(stashRef) }) {
            _ = try? await shell.execute("git stash apply stash@{\(idx)} 2>/dev/null")
          }
        }
      }
    }

    return point
  }

  /// Get the current fork depth.
  public var forkDepth: Int { forkStack.count }

  /// Get the current fork stack for display.
  public var forkHistory: [ForkPoint] { forkStack }

  private func isGitRepo() async -> Bool {
    guard let result = try? await shell.execute("git rev-parse --git-dir 2>/dev/null") else {
      return false
    }
    return result.exitCode == 0
  }
}
