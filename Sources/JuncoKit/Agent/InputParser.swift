// InputParser.swift — Parse user input for @file references, URLs, and sanitization
//
// Extracts @file references and URLs from queries, sanitizes input
// for prompt injection, and handles special syntax.

import Foundation

/// Parsed user input with extracted metadata.
public struct ParsedInput: Sendable {
  /// The query text with @references replaced by resolved paths.
  public let query: String
  /// File paths extracted from @references.
  public let referencedFiles: [String]
  /// URLs extracted from the query.
  public let urls: [URL]
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

  /// Parse input: extract @file refs, URLs, detect paste, sanitize.
  public func parse(_ raw: String) -> ParsedInput {
    let isPaste = raw.count > Config.pasteThreshold

    // Extract URLs first (before @-ref parsing could mangle them)
    let urls = extractURLs(from: raw)

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
      } else if let fuzzyMatch = fuzzyMatchFile(path) {
        referencedFiles.append(fuzzyMatch)
        cleanQuery = cleanQuery.replacingOccurrences(of: "@\(path)", with: fuzzyMatch)
      }
    }

    return ParsedInput(
      query: sanitize(cleanQuery.trimmingCharacters(in: .whitespacesAndNewlines)),
      referencedFiles: referencedFiles,
      urls: urls,
      isPaste: isPaste,
      raw: raw
    )
  }

  // MARK: - URL Extraction

  /// Extract URLs from text using NSDataDetector.
  private func extractURLs(from text: String) -> [URL] {
    guard let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    ) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return detector.matches(in: text, range: range).compactMap { match in
      guard let r = Range(match.range, in: text) else { return nil }
      return URL(string: String(text[r]))
    }
  }

  // MARK: - File Matching

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

  // MARK: - Sanitization

  /// Sanitize query text for safe prompt injection.
  public func sanitize(_ text: String) -> String {
    var s = text
    // Remove ANSI escape sequences
    s = s.replacingOccurrences(
      of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression
    )
    // Collapse excessive whitespace
    s = s.replacingOccurrences(
      of: "\\s{3,}", with: "  ", options: .regularExpression
    )
    return s
  }
}
