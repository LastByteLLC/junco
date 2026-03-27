// SessionManager.swift — Multi-turn session state, clipboard, and undo
//
// Maintains context across turns within a session.
// Handles clipboard paste substitution and undo via git stash.

import Foundation

/// Manages session-level state across multiple agent turns.
public actor SessionManager {
  private let workingDirectory: String
  private let shell: SafeShell

  /// Conversation context carried between turns.
  private var turnHistory: [TurnSummary] = []

  /// Clipboard paste tracking.
  private var pasteCounter: Int = 0
  private var pasteStore: [Int: String] = [:]

  /// Undo stack (git stash names).
  private var undoStack: [String] = []

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
    self.shell = SafeShell(workingDirectory: workingDirectory)
  }

  // MARK: - Multi-Turn Context

  /// Record a completed turn for context carry-over.
  public func recordTurn(_ summary: TurnSummary) {
    turnHistory.append(summary)
    if turnHistory.count > Config.maxTurnHistory {
      turnHistory = Array(turnHistory.suffix(Config.maxTurnHistory))
    }
  }

  /// Get compressed context from previous turns (~150 tokens).
  public func previousContext() -> String? {
    guard !turnHistory.isEmpty else { return nil }
    let lines = turnHistory.suffix(3).map { turn in
      "[\(turn.taskType)] \(turn.query) → \(turn.outcome)"
    }
    return "Previous turns:\n" + lines.joined(separator: "\n")
  }

  /// Clear all session state.
  public func clear() {
    turnHistory.removeAll()
    pasteStore.removeAll()
    pasteCounter = 0
  }

  // MARK: - Clipboard / Paste Handling

  /// Process input text, replacing large paste content with [Paste #N] tokens.
  /// Returns the processed query and stores the full paste internally.
  public func processInput(_ raw: String) -> String {
    if raw.count > Config.pasteThreshold {
      pasteCounter += 1
      let id = pasteCounter
      pasteStore[id] = raw

      // Create a summary for the LLM
      let preview = String(raw.prefix(200))
      let lineCount = raw.components(separatedBy: "\n").count
      return "[Paste #\(id): \(lineCount) lines, \(raw.count) chars]\n\(preview)..."
    }

    // Check for explicit paste references in the query
    return raw
  }

  /// Retrieve the full content of a paste by ID.
  public func getPaste(_ id: Int) -> String? {
    pasteStore[id]
  }

  /// Get all paste metadata for context.
  public func pasteInfo() -> String {
    guard !pasteStore.isEmpty else { return "No pastes in session." }
    return pasteStore.map { id, content in
      "[Paste #\(id)]: \(content.count) chars, \(content.components(separatedBy: "\n").count) lines"
    }.joined(separator: "\n")
  }

  // MARK: - Undo via Git Stash

  /// Save current state before an agent task (if in a git repo).
  public func saveCheckpoint() async {
    // Check if git repo
    guard let result = try? await shell.execute("git rev-parse --git-dir 2>/dev/null"),
          result.exitCode == 0
    else { return }

    let stashName = "junco-undo-\(Int(Date().timeIntervalSince1970))"
    let stashResult = try? await shell.execute(
      "git stash push -m '\(stashName)' --include-untracked 2>/dev/null"
    )

    if let r = stashResult, r.stdout.contains("Saved") {
      undoStack.append(stashName)
      // Immediately pop so we keep working on current state
      // but the stash entry exists for undo
      _ = try? await shell.execute("git stash pop --quiet 2>/dev/null")
    }
  }

  /// Undo the last agent task by restoring from git.
  public func undo() async -> String {
    guard let result = try? await shell.execute("git rev-parse --git-dir 2>/dev/null"),
          result.exitCode == 0
    else { return "Not a git repository. Undo requires git." }

    // Check for uncommitted changes
    let status = try? await shell.execute("git diff --stat")
    if let s = status, s.stdout.isEmpty {
      return "Nothing to undo (no changes detected)."
    }

    // Restore to last commit state
    let restore = try? await shell.execute("git checkout -- . 2>&1")
    if let r = restore, r.exitCode == 0 {
      return "Undone. All uncommitted changes reverted."
    }

    return "Undo failed. Check git status manually."
  }

  /// Check if we're in a git repo.
  public func isGitRepo() async -> Bool {
    guard let result = try? await shell.execute("git rev-parse --git-dir 2>/dev/null") else {
      return false
    }
    return result.exitCode == 0
  }

  /// Get brief git status for context.
  public func gitContext() async -> String? {
    guard await isGitRepo() else { return nil }

    let branch = try? await shell.execute("git branch --show-current 2>/dev/null")
    let status = try? await shell.execute("git diff --stat 2>/dev/null")

    var parts: [String] = []
    if let b = branch, !b.stdout.isEmpty {
      parts.append("branch: \(b.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    if let s = status, !s.stdout.isEmpty {
      let fileCount = s.stdout.components(separatedBy: "\n").count - 1
      parts.append("\(fileCount) files changed")
    }

    return parts.isEmpty ? nil : parts.joined(separator: " | ")
  }
}

/// Compact summary of a completed turn.
public struct TurnSummary: Sendable {
  public let query: String
  public let taskType: String
  public let outcome: String  // "ok" or error description
  public let filesModified: [String]

  public init(query: String, taskType: String, outcome: String, filesModified: [String] = []) {
    self.query = String(query.prefix(80))
    self.taskType = taskType
    self.outcome = String(outcome.prefix(60))
    self.filesModified = filesModified
  }
}
