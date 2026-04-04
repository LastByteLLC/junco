// TreeSitterExtractor.swift — Tree-sitter AST-based symbol extraction
//
// Replaces regex-based extraction with proper AST parsing via tree-sitter.
// Handles nested types, generics, extensions, computed properties, and
// all Swift syntax that regex misses.
//
// Falls back to regex extraction (FileIndexer.extractSwiftSymbols) if
// tree-sitter parsing fails.

import Foundation
import SwiftTreeSitter
import TreeSitterSwiftGrammar

/// Extracts symbols from Swift files using tree-sitter AST parsing.
public struct TreeSitterExtractor: Sendable {
  private let language: Language

  public init() {
    self.language = Language(language: tree_sitter_swift())
  }

  // MARK: - Symbol Extraction

  /// Extract all symbols from a Swift file using the tree-sitter AST.
  public func extract(from content: String, file: String) -> [IndexEntry] {
    let parser = Parser()
    do {
      try parser.setLanguage(language)
    } catch {
      return []
    }

    guard let tree = parser.parse(content) else { return [] }
    guard let root = tree.rootNode else { return [] }

    let lines = content.components(separatedBy: "\n")
    let utf16 = Array(content.utf16)
    var entries: [IndexEntry] = []

    // Add file-level entry
    let firstLine = lines.first ?? ""
    entries.append(IndexEntry(
      filePath: file, symbolName: file, kind: .file,
      lineNumber: 1, snippet: String(firstLine.prefix(200))
    ))

    // Walk the AST
    walkNode(root, lines: lines, utf16: utf16, file: file, entries: &entries, depth: 0)

    return entries
  }

  /// Extract type USAGES from a file — which known symbols are referenced.
  /// Used to build the reference graph.
  public func extractUsages(
    from content: String,
    knownSymbols: Set<String>
  ) -> [(symbol: String, line: Int)] {
    let parser = Parser()
    do {
      try parser.setLanguage(language)
    } catch {
      return []
    }

    guard let tree = parser.parse(content) else { return [] }
    guard let root = tree.rootNode else { return [] }

    let utf16 = Array(content.utf16)
    var usages: [(symbol: String, line: Int)] = []
    collectUsages(root, utf16: utf16, knownSymbols: knownSymbols, usages: &usages)
    return usages
  }

  // MARK: - AST Walking

  private func walkNode(
    _ node: Node,
    lines: [String],
    utf16: [UInt16],
    file: String,
    entries: inout [IndexEntry],
    depth: Int
  ) {
    let nodeType = node.nodeType ?? ""

    switch nodeType {
    // class_declaration covers struct, class, enum, actor, AND extension in this grammar
    case "class_declaration":
      handleClassDeclaration(node, lines: lines, utf16: utf16, file: file, entries: &entries)

    case "protocol_declaration":
      if let nameNode = findChild(node, ofType: "type_identifier") {
        let name = nodeText(nameNode, utf16: utf16)
        let line = Int(node.pointRange.lowerBound.row) + 1
        let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 5)
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .type,
          lineNumber: line, snippet: snippet
        ))
      }

    case "function_declaration":
      // Check if it's an init (has `init` child instead of `func` + name)
      if hasChild(node, ofType: "init") {
        let line = Int(node.pointRange.lowerBound.row) + 1
        let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 3)
        entries.append(IndexEntry(
          filePath: file, symbolName: "init", kind: .function,
          lineNumber: line, snippet: snippet
        ))
      } else if let nameNode = findChild(node, ofType: "simple_identifier") {
        let name = nodeText(nameNode, utf16: utf16)
        let line = Int(node.pointRange.lowerBound.row) + 1
        let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 5)
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .function,
          lineNumber: line, snippet: snippet
        ))
      }

    case "property_declaration":
      if depth <= 3 {  // Inside type body, not inside functions
        if let patternNode = findChild(node, ofType: "pattern") {
          if let nameNode = findChild(patternNode, ofType: "simple_identifier") {
            let name = nodeText(nameNode, utf16: utf16)
            if name.count >= 2 && name != "self" {
              let line = Int(node.pointRange.lowerBound.row) + 1
              let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 1)
              entries.append(IndexEntry(
                filePath: file, symbolName: name, kind: .property,
                lineNumber: line, snippet: snippet
              ))
            }
          }
        }
      }

    case "import_declaration":
      if let identNode = findChild(node, ofType: "identifier") {
        if let nameNode = findChild(identNode, ofType: "simple_identifier") {
          let name = nodeText(nameNode, utf16: utf16)
          let line = Int(node.pointRange.lowerBound.row) + 1
          entries.append(IndexEntry(
            filePath: file, symbolName: name, kind: .import,
            lineNumber: line, snippet: snippetFrom(lines: lines, startLine: line - 1, count: 1)
          ))
        }
      }

    case "typealias_declaration":
      if let nameNode = findChild(node, ofType: "type_identifier") {
        let name = nodeText(nameNode, utf16: utf16)
        let line = Int(node.pointRange.lowerBound.row) + 1
        let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 1)
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .type,
          lineNumber: line, snippet: snippet
        ))
      }

    case "enum_entry":
      // Enum cases can have multiple names (case red, green, blue)
      for i in 0..<node.childCount {
        if let child = node.child(at: i), child.nodeType == "simple_identifier" {
          let name = nodeText(child, utf16: utf16)
          let line = Int(child.pointRange.lowerBound.row) + 1
          let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 1)
          entries.append(IndexEntry(
            filePath: file, symbolName: name, kind: .property,
            lineNumber: line, snippet: snippet
          ))
        }
      }

    default:
      break
    }

    // Recurse into children
    for i in 0..<node.childCount {
      if let child = node.child(at: i) {
        walkNode(child, lines: lines, utf16: utf16, file: file, entries: &entries, depth: depth + 1)
      }
    }
  }

  /// Handle class_declaration which covers struct/class/enum/actor/extension.
  private func handleClassDeclaration(
    _ node: Node,
    lines: [String],
    utf16: [UInt16],
    file: String,
    entries: inout [IndexEntry]
  ) {
    // Determine what kind of declaration by checking the first keyword child
    let isExtension = hasChild(node, ofType: "extension")

    if isExtension {
      // Extension: type name is in user_type > type_identifier
      if let userTypeNode = findChild(node, ofType: "user_type") {
        if let typeIdNode = findChild(userTypeNode, ofType: "type_identifier") {
          let typeName = nodeText(typeIdNode, utf16: utf16)
          let line = Int(node.pointRange.lowerBound.row) + 1
          let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 3)

          var fullName = "extension \(typeName)"
          // Check for conformances (inheritance_specifier children)
          let conformances = allChildren(node, ofType: "inheritance_specifier")
          if !conformances.isEmpty {
            let names = conformances.compactMap { spec -> String? in
              guard let ut = findChild(spec, ofType: "user_type"),
                    let ti = findChild(ut, ofType: "type_identifier") else { return nil }
              return nodeText(ti, utf16: utf16)
            }
            if !names.isEmpty {
              fullName += "+ \(names.joined(separator: ", "))"
            }
          }

          entries.append(IndexEntry(
            filePath: file, symbolName: fullName, kind: .type,
            lineNumber: line, snippet: snippet
          ))
        }
      }
    } else {
      // struct/class/enum/actor: name is direct type_identifier child
      if let nameNode = findChild(node, ofType: "type_identifier") {
        let name = nodeText(nameNode, utf16: utf16)
        let line = Int(node.pointRange.lowerBound.row) + 1
        let snippet = snippetFrom(lines: lines, startLine: line - 1, count: 5)
        entries.append(IndexEntry(
          filePath: file, symbolName: name, kind: .type,
          lineNumber: line, snippet: snippet
        ))
      }
    }
  }

  // MARK: - Usage Extraction (for Reference Graph)

  private func collectUsages(
    _ node: Node,
    utf16: [UInt16],
    knownSymbols: Set<String>,
    usages: inout [(symbol: String, line: Int)]
  ) {
    let nodeType = node.nodeType ?? ""

    if nodeType == "type_identifier" || nodeType == "simple_identifier" {
      let text = nodeText(node, utf16: utf16)
      if knownSymbols.contains(text) {
        let line = Int(node.pointRange.lowerBound.row) + 1
        usages.append((text, line))
      }
    }

    // Recurse
    for i in 0..<node.childCount {
      if let child = node.child(at: i) {
        collectUsages(child, utf16: utf16, knownSymbols: knownSymbols, usages: &usages)
      }
    }
  }

  // MARK: - Helpers

  /// Extract text of a node using byte range on UTF-16 content.
  /// SwiftTreeSitter parses strings as UTF-16, so byteRange offsets are into UTF-16 data.
  private func nodeText(_ node: Node, utf16: [UInt16]) -> String {
    let startByte = Int(node.byteRange.lowerBound)
    let endByte = Int(node.byteRange.upperBound)
    let start = startByte / 2
    let end = endByte / 2
    guard start >= 0, end <= utf16.count, start < end else { return "" }
    return String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start)
  }

  /// Find first direct child node matching a node type.
  private func findChild(_ node: Node, ofType type: String) -> Node? {
    for i in 0..<node.childCount {
      if let child = node.child(at: i), child.nodeType == type {
        return child
      }
    }
    return nil
  }

  /// Check if a node has a direct child of the given type.
  private func hasChild(_ node: Node, ofType type: String) -> Bool {
    findChild(node, ofType: type) != nil
  }

  /// Find all direct children matching a node type.
  private func allChildren(_ node: Node, ofType type: String) -> [Node] {
    var result: [Node] = []
    for i in 0..<node.childCount {
      if let child = node.child(at: i), child.nodeType == type {
        result.append(child)
      }
    }
    return result
  }

  /// Extract a snippet of N lines starting from a given line.
  private func snippetFrom(lines: [String], startLine: Int, count: Int) -> String {
    let end = min(startLine + count, lines.count)
    guard startLine < end else { return "" }
    return lines[startLine..<end].joined(separator: "\n").prefix(300).description
  }
}
