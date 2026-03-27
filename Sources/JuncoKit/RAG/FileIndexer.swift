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
    extensions: [String] = ["swift", "js", "ts"],
    maxFiles: Int = 100
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

      // Extract symbols based on language
      switch ext {
      case "swift":
        entries.append(contentsOf: extractSwiftSymbols(from: content, file: file))
      case "js", "ts":
        entries.append(contentsOf: extractJSSymbols(from: content, file: file))
      default:
        break
      }
    }

    return entries
  }

  // MARK: - Swift Symbol Extraction (regex-based, pre-SwiftSyntax)

  private func extractSwiftSymbols(from content: String, file: String) -> [IndexEntry] {
    var entries: [IndexEntry] = []
    let lines = content.components(separatedBy: "\n")

    for (i, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Functions
      if let match = trimmed.firstMatch(of: /(?:public\s+|private\s+|internal\s+|open\s+)?func\s+(\w+)/) {
        let name = String(match.1)
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .function,
          lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      }

      // Types (struct, class, enum, actor, protocol)
      if let match = trimmed.firstMatch(of: /(?:public\s+|private\s+)?(?:struct|class|enum|actor|protocol)\s+(\w+)/) {
        let name = String(match.1)
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .type,
          lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      }

      // Imports
      if let match = trimmed.firstMatch(of: /^import\s+(\w+)/) {
        entries.append(IndexEntry(
          filePath: file, symbolName: String(match.1), kind: .import,
          lineNumber: i + 1, snippet: trimmed
        ))
      }
    }

    return entries
  }

  // MARK: - JavaScript/TypeScript Symbol Extraction

  private func extractJSSymbols(from content: String, file: String) -> [IndexEntry] {
    var entries: [IndexEntry] = []
    let lines = content.components(separatedBy: "\n")

    for (i, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Functions: function name, const name = () =>, export function
      if let match = trimmed.firstMatch(of: /(?:export\s+)?(?:async\s+)?function\s+(\w+)/) {
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: String(match.1), kind: .function,
          lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      } else if let match = trimmed.firstMatch(of: /(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(/) {
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: String(match.1), kind: .function,
          lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      }

      // Classes
      if let match = trimmed.firstMatch(of: /(?:export\s+)?class\s+(\w+)/) {
        let snippet = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
        entries.append(IndexEntry(
          filePath: file, symbolName: String(match.1), kind: .type,
          lineNumber: i + 1, snippet: String(snippet.prefix(200))
        ))
      }

      // Imports
      if trimmed.hasPrefix("import ") || trimmed.contains("require(") {
        entries.append(IndexEntry(
          filePath: file, symbolName: trimmed, kind: .import,
          lineNumber: i + 1, snippet: String(trimmed.prefix(120))
        ))
      }
    }

    return entries
  }
}
