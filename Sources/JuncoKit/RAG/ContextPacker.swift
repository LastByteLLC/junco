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
    // Pre-compute BM25 statistics
    let queryTerms = tokenize(query)
    let idf = computeIDF(queryTerms: queryTerms, index: index)
    let totalTerms = index.reduce(0) { $0 + tokenize($1.symbolName + " " + $1.snippet).count }
    let avgDocLen = index.isEmpty ? 1.0 : Double(totalTerms) / Double(index.count)

    // Score and rank entries using BM25
    var scored = index.map { entry in
      (entry: entry, score: score(entry: entry, query: query, preferredFiles: preferredFiles, idf: idf, avgDocLen: avgDocLen))
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

  // MARK: - BM25 Scoring

  // BM25 parameters
  private static let k1 = 1.2   // Term frequency saturation
  private static let b = 0.75   // Document length normalization

  // Field weights: symbol name matches matter most
  private static let nameWeight = 3.0
  private static let pathWeight = 2.0
  private static let snippetWeight = 1.0

  /// Score an index entry against a query using BM25 with field weights.
  private func score(
    entry: IndexEntry,
    query: String,
    preferredFiles: [String],
    idf: [String: Double],
    avgDocLen: Double
  ) -> Double {
    let queryTerms = tokenize(query)
    let nameTerms = tokenize(entry.symbolName)
    let pathTerms = tokenize(entry.filePath)
    let snippetTerms = tokenize(entry.snippet)

    // Document length for normalization
    let docLen = Double(nameTerms.count + pathTerms.count + snippetTerms.count)

    var score = 0.0
    for term in queryTerms {
      let termIdf = idf[term] ?? 0.1

      // Count term frequency in each field
      let nameTf = nameTerms.contains(term) ? 1.0 : 0.0
      let pathTf = pathTerms.contains(term) ? 1.0 : 0.0
      let snippetTf = snippetTerms.contains(term) ? 1.0 : 0.0

      // Weighted TF across fields
      let weightedTf = nameTf * Self.nameWeight + pathTf * Self.pathWeight + snippetTf * Self.snippetWeight

      // BM25 TF normalization
      let tfNorm = (weightedTf * (Self.k1 + 1)) /
        (weightedTf + Self.k1 * (1 - Self.b + Self.b * docLen / max(1, avgDocLen)))

      score += termIdf * tfNorm

      // Prefix match bonus (smaller than exact)
      if nameTerms.contains(where: { $0.hasPrefix(term) || term.hasPrefix($0) }) {
        score += termIdf * 0.3
      }
    }

    // Boost for preferred files
    if preferredFiles.contains(entry.filePath) {
      score += 3.0
    }

    // Kind boost
    switch entry.kind {
    case .function: score *= 1.5
    case .type: score *= 1.3
    case .property: score *= 1.2
    case .file: score *= 1.0
    case .import: score *= 0.3
    }

    return score
  }

  /// Pre-compute IDF (inverse document frequency) for query terms.
  /// Rare terms get higher weight — "Orchestrator" matters more than "func".
  private func computeIDF(queryTerms: Set<String>, index: [IndexEntry]) -> [String: Double] {
    let n = Double(index.count)
    var idf: [String: Double] = [:]
    for term in queryTerms {
      let df = Double(index.filter { entry in
        let text = (entry.symbolName + " " + entry.snippet + " " + entry.filePath).lowercased()
        return text.contains(term)
      }.count)
      idf[term] = log((n - df + 0.5) / (df + 0.5) + 1.0)
    }
    return idf
  }

  /// Simple tokenizer: lowercase, split on non-alphanumeric, filter short tokens.
  private func tokenize(_ text: String) -> Set<String> {
    Set(
      text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 2 }
    )
  }
}
