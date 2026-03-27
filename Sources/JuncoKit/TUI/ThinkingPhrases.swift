// ThinkingPhrases.swift — Stage-specific status phrases with spinner
//
// Provides contextual phrases for each pipeline stage.
// Ships with built-in phrases; can load custom phrases from .junco/phrases.json.

import Foundation

/// Provides thinking/status phrases for each pipeline stage.
public struct ThinkingPhrases: Sendable {
  private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  private static let builtin: [String: [String]] = [
    "classify": [
      "Reading your intent...",
      "Understanding the task...",
      "Figuring out what you need...",
    ],
    "strategy": [
      "Choosing an approach...",
      "Considering options...",
      "Picking a strategy...",
    ],
    "plan": [
      "Planning steps...",
      "Breaking it down...",
      "Mapping out the work...",
    ],
    "execute": [
      "Working...",
      "Making changes...",
      "Executing the plan...",
    ],
    "read": [
      "Reading code...",
      "Scanning the file...",
      "Loading context...",
    ],
    "edit": [
      "Editing code...",
      "Applying changes...",
      "Rewriting...",
    ],
    "bash": [
      "Running command...",
      "Executing in shell...",
    ],
    "search": [
      "Searching codebase...",
      "Scanning for matches...",
    ],
    "reflect": [
      "Reviewing results...",
      "Learning from this...",
      "Wrapping up...",
    ],
    "fetch": [
      "Fetching URL...",
      "Downloading content...",
    ],
  ]

  private let custom: [String: [String]]

  public init(projectDirectory: String? = nil) {
    if let dir = projectDirectory {
      let path = (dir as NSString).appendingPathComponent(".junco/phrases.json")
      if let data = FileManager.default.contents(atPath: path),
         let parsed = try? JSONDecoder().decode([String: [String]].self, from: data) {
        self.custom = parsed
      } else {
        self.custom = [:]
      }
    } else {
      self.custom = [:]
    }
  }

  /// Get a random phrase for a stage.
  public func phrase(for stage: String) -> String {
    let candidates = (custom[stage] ?? []) + (Self.builtin[stage] ?? Self.builtin["execute"]!)
    return candidates.randomElement() ?? "Working..."
  }

  /// Get a spinner frame for the given tick count.
  public static func spinner(tick: Int) -> String {
    spinnerFrames[tick % spinnerFrames.count]
  }

  /// Format a status line with spinner + phrase.
  public func status(stage: String, tick: Int) -> String {
    "\(Self.spinner(tick: tick)) \(phrase(for: stage))"
  }
}
