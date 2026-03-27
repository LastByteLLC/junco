// InputParser.swift — Parse user input for @file references, directives, and sanitization
//
// Extracts @file references from queries, sanitizes input for prompt injection,
// and handles special syntax.

import Foundation

/// Parsed user input with extracted metadata.
public struct ParsedInput: Sendable {
  /// The query text with @references removed.
  public let query: String
  /// File paths extracted from @references.
  public let referencedFiles: [String]
  /// Whether the input was detected as a paste.
  public let isPaste: Bool
  /// Original raw input.
  public let raw: String
}

/// Parses and processes raw user input.
public struct InputParser: Sendable {
  private let files: FileTools

  public init(workingDirectory: String) {
    self.files = FileTools(workingDirectory: workingDirectory)
  }

  /// Parse input, extracting @file references and sanitizing.
  public func parse(_ raw: String) -> ParsedInput {
    let isPaste = raw.count > Config.pasteThreshold

    // Extract @file references
    var referencedFiles: [String] = []
    var cleanQuery = raw

    let pattern = /@([\w\/\.\-]+\.\w+)/
    let matches = raw.matches(of: pattern)
    for match in matches {
      let path = String(match.1)
      if files.exists(path) {
        referencedFiles.append(path)
        cleanQuery = cleanQuery.replacingOccurrences(of: "@\(path)", with: path)
      } else {
        // Try fuzzy file matching
        if let fuzzyMatch = fuzzyMatchFile(path) {
          referencedFiles.append(fuzzyMatch)
          cleanQuery = cleanQuery.replacingOccurrences(of: "@\(path)", with: fuzzyMatch)
        }
      }
    }

    return ParsedInput(
      query: cleanQuery.trimmingCharacters(in: .whitespacesAndNewlines),
      referencedFiles: referencedFiles,
      isPaste: isPaste,
      raw: raw
    )
  }

  /// Fuzzy match a partial file name against project files.
  private func fuzzyMatchFile(_ partial: String) -> String? {
    let allFiles = files.listFiles(maxFiles: Config.maxListFiles)
    let lower = partial.lowercased()

    // Exact basename match
    if let match = allFiles.first(where: {
      ($0 as NSString).lastPathComponent.lowercased() == lower
    }) {
      return match
    }

    // Contains match
    if let match = allFiles.first(where: {
      $0.lowercased().contains(lower)
    }) {
      return match
    }

    return nil
  }

  /// Sanitize query text for safe prompt injection.
  /// Escapes sequences that could confuse the LLM's instruction following.
  public func sanitize(_ text: String) -> String {
    var sanitized = text
    // Remove ANSI escape sequences
    sanitized = sanitized.replacingOccurrences(
      of: "\u{1B}\\[[0-9;]*[a-zA-Z]",
      with: "",
      options: .regularExpression
    )
    // Collapse excessive whitespace
    sanitized = sanitized.replacingOccurrences(
      of: "\\s{3,}",
      with: "  ",
      options: .regularExpression
    )
    return sanitized
  }
}
