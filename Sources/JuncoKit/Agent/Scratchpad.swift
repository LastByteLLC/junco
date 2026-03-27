// Scratchpad.swift — Persistent project-level notes the agent writes for itself
//
// A simple key-value notepad that persists across sessions.
// Used by the agent to remember project-specific patterns,
// conventions, and context that don't fit in reflections.

import Foundation

/// Project-scoped persistent notepad.
public struct Scratchpad: Sendable {
  private let path: String

  public init(projectDirectory: String) {
    let dir = (projectDirectory as NSString).appendingPathComponent(Config.projectDirName)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    self.path = (dir as NSString).appendingPathComponent("scratchpad.json")
  }

  /// Read all notes.
  public func readAll() -> [String: String] {
    guard let data = FileManager.default.contents(atPath: path),
          let notes = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return notes
  }

  /// Write a note.
  public func write(key: String, value: String) {
    var notes = readAll()
    notes[key] = value

    // Auto-compact: keep max 20 notes
    if notes.count > 20 {
      let sorted = notes.sorted { $0.key < $1.key }
      notes = Dictionary(uniqueKeysWithValues: Array(sorted.suffix(20)))
    }

    guard let data = try? JSONEncoder().encode(notes) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
  }

  /// Remove a note.
  public func remove(key: String) {
    var notes = readAll()
    notes.removeValue(forKey: key)
    guard let data = try? JSONEncoder().encode(notes) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
  }

  /// Format for prompt injection (~100 tokens).
  public func promptContext(budget: Int = 100) -> String? {
    let notes = readAll()
    guard !notes.isEmpty else { return nil }

    let formatted = notes.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
    let truncated = TokenBudget.truncate(formatted, toTokens: budget)
    return "Project notes:\n\(truncated)"
  }

  public var count: Int { readAll().count }
}
