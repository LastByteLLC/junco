// SymbolIndex.swift — Inverted symbol index for O(1) code search
//
// Wraps FileIndexer output with dictionary-based lookups:
//   nameIndex:  symbol name → [entries]  (exact match, case-insensitive)
//   wordIndex:  lowercase word → [entries]  (any word in name or snippet)
//   fileIndex:  file path → [entries]  (all symbols in a file)
//
// Multi-term search scores by intersection (hits matching multiple terms rank higher).
// Declaration sites score higher than references.

import Foundation

/// Fast searchable index over project symbols.
/// Built once from FileIndexer output, supports O(1) lookups.
public struct SymbolIndex: Sendable {
  private let entries: [IndexEntry]

  /// Exact symbol name → entry indices (case-insensitive).
  private let nameIndex: [String: [Int]]

  /// Lowercase word → entry indices (from name + snippet tokenization).
  private let wordIndex: [String: [Int]]

  /// File path → entry indices.
  private let fileIndex: [String: [Int]]

  /// Build from FileIndexer output.
  public init(entries: [IndexEntry]) {
    self.entries = entries

    var names: [String: [Int]] = [:]
    var words: [String: [Int]] = [:]
    var files: [String: [Int]] = [:]

    for (i, entry) in entries.enumerated() {
      // Name index (case-insensitive)
      let lowerName = entry.symbolName.lowercased()
      names[lowerName, default: []].append(i)

      // File index
      files[entry.filePath, default: []].append(i)

      // Word index — tokenize name and first line of snippet
      let searchableText = entry.symbolName + " " +
        (entry.snippet.components(separatedBy: "\n").first ?? "")
      let tokens = Self.tokenize(searchableText)
      for token in tokens {
        words[token, default: []].append(i)
      }
    }

    self.nameIndex = names
    self.wordIndex = words
    self.fileIndex = files
  }

  // MARK: - Lookups

  /// O(1) exact name match (case-insensitive).
  public func findByName(_ name: String) -> [IndexEntry] {
    let indices = nameIndex[name.lowercased()] ?? []
    return indices.map { entries[$0] }
  }

  /// O(1) word match in name or snippet.
  public func findByWord(_ word: String) -> [IndexEntry] {
    let indices = wordIndex[word.lowercased()] ?? []
    return indices.map { entries[$0] }
  }

  /// O(1) file lookup.
  public func findByFile(_ path: String) -> [IndexEntry] {
    let indices = fileIndex[path] ?? []
    return indices.map { entries[$0] }
  }

  /// Multi-term search with intersection scoring.
  /// Entries matching more terms score higher. Declarations boosted.
  public func search(terms: [String]) -> [(entry: IndexEntry, score: Double)] {
    guard !terms.isEmpty else { return [] }

    // Collect all candidate indices with per-term scores
    var scores: [Int: Double] = [:]

    for term in terms {
      let lower = term.lowercased()

      // Exact name match — highest value
      for i in nameIndex[lower] ?? [] {
        scores[i, default: 0] += 10.0
      }

      // Word match — good value
      for i in wordIndex[lower] ?? [] {
        // Don't double-count if already matched by name
        if nameIndex[lower]?.contains(i) != true {
          scores[i, default: 0] += 3.0
        }
      }
    }

    // Declaration boost
    var results = scores.map { (index, score) -> (entry: IndexEntry, score: Double) in
      let entry = entries[index]
      var boosted = score
      if entry.kind == .type { boosted += 2.0 }
      if entry.kind == .function { boosted += 1.0 }
      if entry.kind == .import { boosted -= 1.0 }
      // File-level entries score low unless explicitly matched by name
      if entry.kind == .file && score < 10.0 { boosted -= 2.0 }
      return (entry, boosted)
    }

    results.sort { $0.score > $1.score }
    return results
  }

  // MARK: - Stats

  public var entryCount: Int { entries.count }
  public var functionCount: Int { entries.filter { $0.kind == .function }.count }
  public var typeCount: Int { entries.filter { $0.kind == .type }.count }
  public var fileCount: Int { entries.filter { $0.kind == .file }.count }
  public var uniqueFiles: Int { fileIndex.count }

  // MARK: - Incremental Update

  /// Create a new index with entries for one file replaced.
  /// Used for incremental updates when FileWatcher detects changes.
  public func replacingFile(_ path: String, with newEntries: [IndexEntry]) -> SymbolIndex {
    var updated = entries.filter { $0.filePath != path }
    updated.append(contentsOf: newEntries)
    return SymbolIndex(entries: updated)
  }

  // MARK: - Tokenization

  /// Tokenize text into lowercase words (3+ chars, no stop words).
  static func tokenize(_ text: String) -> Set<String> {
    Set(
      text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 3 && !StopWords.contains($0) }
    )
  }
}
