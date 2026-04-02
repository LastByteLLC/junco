// IgnoreFilter.swift — .juncoignore support
//
// Parses .juncoignore (gitignore-style) to exclude directories/files
// from indexing, search, and listing. Always excludes .build, .git,
// .build, DerivedData regardless of config.

import Foundation

/// Filters files based on .juncoignore patterns.
public struct IgnoreFilter: Sendable {
  private let patterns: [String]

  /// Always-excluded directories (hardcoded).
  private static let builtinIgnores = [
    ".build", ".git", ".junco",
    ".claude", ".codex", ".vscode",
    "DerivedData", ".swiftpm",
    "Pods", "build",
    "Samples", "fixtures", "Training",
    "node_modules", "vendor",
  ]

  public init(workingDirectory: String) {
    let ignorePath = (workingDirectory as NSString).appendingPathComponent(".juncoignore")
    var custom: [String] = []
    if let content = try? String(contentsOfFile: ignorePath, encoding: .utf8) {
      custom = content.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }  // Strip trailing /
    }
    self.patterns = Self.builtinIgnores + custom
  }

  /// Check if a relative path should be ignored.
  public func shouldIgnore(_ relativePath: String) -> Bool {
    let components = relativePath.components(separatedBy: "/")

    for pattern in patterns {
      // Directory match: any component equals the pattern
      if components.contains(pattern) { return true }
      // Prefix match: path starts with pattern/
      if relativePath.hasPrefix(pattern + "/") || relativePath == pattern { return true }
      // Glob suffix match: *.ext
      if pattern.hasPrefix("*.") {
        let ext = String(pattern.dropFirst(2))
        if relativePath.hasSuffix("." + ext) { return true }
      }
    }
    return false
  }
}
