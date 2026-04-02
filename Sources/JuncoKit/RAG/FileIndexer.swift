// FileIndexer.swift — Indexes project files for retrieval
//
// Extracts symbols (functions, types, imports) from source files
// using lightweight regex-based parsing. Full AST via SwiftSyntax
// will be added when that dependency is integrated.

import Foundation

/// A single indexed entry representing a code symbol or file summary.
public struct IndexEntry: Codable, Sendable {
  public let filePath: String
  public let symbolName: String
  public let kind: SymbolKind
  public let lineNumber: Int
  public let snippet: String  // First ~3 lines of the symbol

  public enum SymbolKind: String, Codable, Sendable {
    case function, type, property, `import`, file
  }
}

/// Indexes project files and extracts searchable symbols.
public struct FileIndexer: Sendable {
  public let workingDirectory: String

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
  }

  /// Index all source files in the project.
  public func indexProject(
    extensions: [String] = ["swift"],
    maxFiles: Int = Config.maxIndexFiles
  ) -> [IndexEntry] {
    let ft = FileTools(workingDirectory: workingDirectory)
    let files = ft.listFiles(extensions: extensions, maxFiles: maxFiles)
    var entries: [IndexEntry] = []

    for file in files {
      guard let content = try? ft.read(path: file, maxTokens: 2000) else { continue }
      let ext = (file as NSString).pathExtension

      // Add file-level entry
      let firstLine = content.prefix(while: { $0 != "\n" })
      entries.append(IndexEntry(
        filePath: file, symbolName: file, kind: .file,
        lineNumber: 1, snippet: String(firstLine)
      ))

      // Extract symbols
      if ext == "swift" {
        entries.append(contentsOf: extractSwiftSymbols(from: content, file: file))
      }
    }

    return entries
  }

  /// Index a single file (for incremental updates).
  public func indexFile(_ path: String) -> [IndexEntry] {
    let ft = FileTools(workingDirectory: workingDirectory)
    guard let content = try? ft.read(path: path, maxTokens: 2000) else { return [] }

    var entries: [IndexEntry] = []
    let firstLine = content.prefix(while: { $0 != "\n" })
    entries.append(IndexEntry(
      filePath: path, symbolName: path, kind: .file,
      lineNumber: 1, snippet: String(firstLine)
    ))

    let ext = (path as NSString).pathExtension
    if ext == "swift" {
      entries.append(contentsOf: extractSwiftSymbols(from: content, file: path))
    }
    return entries
  }

  // MARK: - Index Persistence

  /// Save index to .junco/index.json for fast startup.
  public func saveIndex(_ entries: [IndexEntry]) {
    let dir = (workingDirectory as NSString).appendingPathComponent(Config.projectDirName)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = (dir as NSString).appendingPathComponent("index.json")
    guard let data = try? JSONEncoder().encode(entries) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
  }

  /// Load cached index if available.
  public func loadCachedIndex() -> [IndexEntry]? {
    let path = (workingDirectory as NSString)
      .appendingPathComponent("\(Config.projectDirName)/index.json")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let entries = try? JSONDecoder().decode([IndexEntry].self, from: data)
    else { return nil }
    return entries
  }

  // MARK: - Swift Symbol Extraction (regex-based, pre-SwiftSyntax)

  private func extractSwiftSymbols(from content: String, file: String) -> [IndexEntry] {
    var entries: [IndexEntry] = []
    let lines = content.components(separatedBy: "\n")
    var braceDepth = 0

    for (i, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Track brace depth for context awareness
      let opens = trimmed.filter { $0 == "{" }.count
      let closes = trimmed.filter { $0 == "}" }.count

      // Functions
      if let match = trimmed.firstMatch(of: /(?:public\s+|private\s+|internal\s+|open\s+)?(?:static\s+)?func\s+(\w+)/) {
        let name = String(match.1)
        let snippet = lines[i..<min(i + 5, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .function,
          lineNumber: i + 1, snippet: String(snippet.prefix(300))
        ))
      }

      // Types (struct, class, enum, actor, protocol)
      if let match = trimmed.firstMatch(of: /(?:public\s+|private\s+)?(?:struct|class|enum|actor|protocol)\s+(\w+)/) {
        let name = String(match.1)
        let snippet = lines[i..<min(i + 5, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .type,
          lineNumber: i + 1, snippet: String(snippet.prefix(300))
        ))
      }

      // Extensions (captures type name and optional conformance)
      if let match = trimmed.firstMatch(of: /extension\s+(\w+)(?:\s*:\s*(\w+))?/) {
        let name = String(match.1)
        let conformance = match.2.map { "+ \(String($0))" } ?? ""
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: "extension \(name)\(conformance.isEmpty ? "" : " \(conformance)")",
          kind: .type, lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      }

      // Properties at type level (braceDepth 1 = inside a type body)
      // Skip local variables inside functions (depth 2+)
      if braceDepth <= 1 {
        if let match = trimmed.firstMatch(of: /(?:public\s+|private\s+|internal\s+)?(?:public\s+private\(set\)\s+)?(?:static\s+)?(?:let|var)\s+(\w+)\s*[=:]/) {
          let name = String(match.1)
          // Skip common loop variables and short names
          if name.count >= 2 && name != "self" {
            entries.append(IndexEntry(
              filePath: file, symbolName: name, kind: .property,
              lineNumber: i + 1, snippet: String(trimmed.prefix(200))
            ))
          }
        }
      }

      // Imports
      if let match = trimmed.firstMatch(of: /^import\s+(\w+)/) {
        entries.append(IndexEntry(
          filePath: file, symbolName: String(match.1), kind: .import,
          lineNumber: i + 1, snippet: trimmed
        ))
      }

      braceDepth += opens - closes
      braceDepth = max(0, braceDepth)
    }

    return entries
  }

}
