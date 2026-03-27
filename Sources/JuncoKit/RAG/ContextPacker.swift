// ContextPacker.swift — Selects and packs relevant code into token budget
//
// Given a query and an index, selects the most relevant code snippets
// and packs them into a string that fits within the token budget.
// Uses keyword scoring (BM25-inspired) for ranking.

import Foundation

/// Packs relevant code context into a token-budgeted string.
public struct ContextPacker: Sendable {
  private let files: FileTools
  private let indexer: FileIndexer

  public init(workingDirectory: String) {
    self.files = FileTools(workingDirectory: workingDirectory)
    self.indexer = FileIndexer(workingDirectory: workingDirectory)
  }

  /// Select and pack the most relevant code for a query, within a token budget.
  public func pack(
    query: String,
    index: [IndexEntry],
    budget: Int = 800,
    preferredFiles: [String] = []
  ) -> String {
    // Score and rank entries
    var scored = index.map { entry in
      (entry: entry, score: score(entry: entry, query: query, preferredFiles: preferredFiles))
    }
    scored.sort { $0.score > $1.score }

    // Pack top entries within budget
    var packed = ""
    var tokensUsed = 0
    var includedFiles: Set<String> = []

    for item in scored {
      let entry = item.entry
      guard item.score > 0 else { break }

      // For file entries, include the file content
      if entry.kind == .file, !includedFiles.contains(entry.filePath) {
        guard let content = try? files.read(path: entry.filePath, maxTokens: budget / 3) else {
          continue
        }
        let chunk = "--- \(entry.filePath) ---\n\(content)\n"
        let chunkTokens = TokenBudget.estimate(chunk)
        if tokensUsed + chunkTokens > budget { continue }

        packed += chunk
        tokensUsed += chunkTokens
        includedFiles.insert(entry.filePath)
      } else if entry.kind != .file, !includedFiles.contains(entry.filePath) {
        // For symbol entries, include a focused snippet
        let chunk = "[\(entry.filePath):\(entry.lineNumber)] \(entry.symbolName):\n\(entry.snippet)\n"
        let chunkTokens = TokenBudget.estimate(chunk)
        if tokensUsed + chunkTokens > budget { continue }

        packed += chunk
        tokensUsed += chunkTokens
      }
    }

    return packed.isEmpty ? "(no relevant code found)" : packed
  }

  // MARK: - Keyword Scoring (BM25-inspired)

  /// Score an index entry against a query. Higher = more relevant.
  private func score(
    entry: IndexEntry,
    query: String,
    preferredFiles: [String]
  ) -> Double {
    let queryTerms = tokenize(query)
    let entryTerms = tokenize(entry.symbolName + " " + entry.snippet + " " + entry.filePath)

    var matchScore = 0.0
    for term in queryTerms {
      if entryTerms.contains(term) {
        matchScore += 1.0
      }
      // Partial match bonus (prefix)
      if entryTerms.contains(where: { $0.hasPrefix(term) || term.hasPrefix($0) }) {
        matchScore += 0.5
      }
    }

    // Boost for preferred files
    if preferredFiles.contains(entry.filePath) {
      matchScore += 3.0
    }

    // Boost for types and functions over imports
    switch entry.kind {
    case .function: matchScore *= 1.5
    case .type: matchScore *= 1.3
    case .file: matchScore *= 1.0
    case .property: matchScore *= 1.2
    case .import: matchScore *= 0.3
    }

    return matchScore
  }

  /// Simple tokenizer: lowercase, split on non-alphanumeric, filter short tokens.
  private func tokenize(_ text: String) -> Set<String> {
    let words = text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 2 }
    return Set(words)
  }
}
