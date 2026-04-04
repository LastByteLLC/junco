// ReferenceGraph.swift — Cross-file reference tracking
//
// Maps which files depend on which other files by tracking symbol usage.
// Built from the SymbolIndex + tree-sitter usage extraction.
//
// Use cases:
//   - "What depends on Auth.swift?" → files that use AuthService
//   - Search ranking: boost files related to top search hits
//   - Impact analysis: which files are affected by a change

import Foundation

/// Cross-file dependency graph built from symbol usage analysis.
public struct ReferenceGraph: Sendable {
  /// file → set of files it depends on (uses their symbols).
  public let dependsOn: [String: Set<String>]

  /// file → set of files that depend on it (use its symbols).
  public let dependedOnBy: [String: Set<String>]

  /// Total number of reference edges.
  public let edgeCount: Int

  /// Empty graph (for when building fails or project is too small).
  public static let empty = ReferenceGraph(dependsOn: [:], dependedOnBy: [:], edgeCount: 0)

  // MARK: - Building

  /// Build from a symbol index + file contents.
  /// Uses tree-sitter to extract type usages, cross-references against the index.
  public static func build(
    from symbolIndex: SymbolIndex,
    projectFiles: [String],
    extractor: TreeSitterExtractor,
    fileReader: FileTools
  ) -> ReferenceGraph {
    // Collect all known symbol names → defining file
    var symbolToFile: [String: String] = [:]
    for file in projectFiles {
      for entry in symbolIndex.findByFile(file) {
        if entry.kind == .type || entry.kind == .function {
          symbolToFile[entry.symbolName] = entry.filePath
        }
      }
    }

    let knownSymbols = Set(symbolToFile.keys)
    guard !knownSymbols.isEmpty else { return .empty }

    var dependsOn: [String: Set<String>] = [:]
    var dependedOnBy: [String: Set<String>] = [:]
    var edges = 0

    for file in projectFiles {
      guard let content = try? fileReader.read(path: file, maxTokens: 5000) else { continue }

      let usages = extractor.extractUsages(from: content, knownSymbols: knownSymbols)

      for (symbol, _) in usages {
        guard let definingFile = symbolToFile[symbol] else { continue }
        // Don't count self-references
        guard definingFile != file else { continue }

        if dependsOn[file, default: []].insert(definingFile).inserted {
          edges += 1
        }
        dependedOnBy[definingFile, default: []].insert(file)
      }
    }

    return ReferenceGraph(dependsOn: dependsOn, dependedOnBy: dependedOnBy, edgeCount: edges)
  }

  // MARK: - Queries

  /// Get the 1-hop neighborhood: all files that reference or are referenced by the input files.
  public func neighborhood(of files: Set<String>) -> Set<String> {
    var result = Set<String>()
    for file in files {
      if let deps = dependsOn[file] { result.formUnion(deps) }
      if let refs = dependedOnBy[file] { result.formUnion(refs) }
    }
    // Don't include the seed files themselves
    result.subtract(files)
    return result
  }

  /// Files ranked by how many other files depend on them (most depended-on first).
  public func filesByImportance() -> [(file: String, dependents: Int)] {
    dependedOnBy
      .map { (file: $0.key, dependents: $0.value.count) }
      .sorted { $0.dependents > $1.dependents }
  }

  /// How many files depend on the given file.
  public func dependentCount(for file: String) -> Int {
    dependedOnBy[file]?.count ?? 0
  }

  /// How many files the given file depends on.
  public func dependencyCount(for file: String) -> Int {
    dependsOn[file]?.count ?? 0
  }
}
