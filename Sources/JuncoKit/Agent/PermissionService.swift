// PermissionService.swift — User confirmation before destructive actions
//
// Prompts the user for confirmation before writes, edits, and dangerous
// bash commands. Supports "always allow" rules persisted per-project.

import Foundation

/// Permission decisions.
public enum PermissionDecision: Sendable {
  case allow
  case deny
  case alwaysAllow
}

/// Manages permission prompts for file/shell operations.
public struct PermissionService: Sendable {
  private let rulesPath: String

  public init(workingDirectory: String) {
    let dir = (workingDirectory as NSString).appendingPathComponent(Config.projectDirName)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    self.rulesPath = (dir as NSString).appendingPathComponent("permissions.json")
  }

  /// Check if an action is pre-approved.
  public func isAllowed(tool: String, target: String) -> Bool {
    let rules = loadRules()
    // Check for always-allow rules
    return rules.contains { $0.tool == tool && (target.contains($0.pattern) || $0.pattern == "*") }
  }

  /// Format a permission prompt for the user.
  public static func promptText(tool: String, target: String, detail: String = "") -> String {
    let icon: String
    switch tool {
    case "write": icon = "write"
    case "edit": icon = "edit"
    case "bash": icon = "run"
    default: icon = tool
    }

    var msg = "junco wants to \(icon): \(target)"
    if !detail.isEmpty {
      msg += "\n  \(detail)"
    }
    msg += "\n  [y]es / [n]o / [a]lways allow"
    return msg
  }

  /// Ask the user for permission (reads from stdin in raw mode).
  /// Returns the decision. For non-interactive mode, returns .allow.
  public func ask(tool: String, target: String, detail: String = "") -> PermissionDecision {
    // If pre-approved, skip prompt
    if isAllowed(tool: tool, target: target) {
      return .allow
    }

    // Non-interactive: allow (pipe mode)
    guard isatty(STDIN_FILENO) != 0 else { return .allow }

    let prompt = Self.promptText(tool: tool, target: target, detail: detail)
    print("\n\u{1B}[33m\(prompt)\u{1B}[0m ", terminator: "")
    fflush(stdout)

    // Read single character (temporarily in raw mode if not already)
    guard let line = readLine() else { return .deny }
    let choice = line.lowercased().trimmingCharacters(in: .whitespaces)

    switch choice {
    case "y", "yes", "":
      return .allow
    case "a", "always":
      saveRule(tool: tool, pattern: target)
      return .alwaysAllow
    default:
      return .deny
    }
  }

  // MARK: - Rules Persistence

  private func loadRules() -> [PermissionRule] {
    guard let data = FileManager.default.contents(atPath: rulesPath),
          let rules = try? JSONDecoder().decode([PermissionRule].self, from: data)
    else { return [] }
    return rules
  }

  private func saveRule(tool: String, pattern: String) {
    var rules = loadRules()
    if !rules.contains(where: { $0.tool == tool && $0.pattern == pattern }) {
      rules.append(PermissionRule(tool: tool, pattern: pattern))
      if let data = try? JSONEncoder().encode(rules) {
        try? data.write(to: URL(fileURLWithPath: rulesPath))
      }
    }
  }
}

struct PermissionRule: Codable, Sendable {
  let tool: String
  let pattern: String
}
