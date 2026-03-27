// FileTreeRenderer.swift — Standardized file tree visualization
//
// Renders project file trees with box-drawing characters.
// Used by /files command, explain responses, and structure summaries.
// Supports highlighting modified files and applying .juncoignore.

import Foundation

/// Renders a file listing as a visual tree.
public struct FileTreeRenderer: Sendable {
  private let workingDirectory: String
  private let ignoreFilter: IgnoreFilter

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
    self.ignoreFilter = IgnoreFilter(workingDirectory: workingDirectory)
  }

  /// Render the project file tree as a styled string.
  /// - Parameters:
  ///   - maxDepth: Maximum directory depth to show.
  ///   - maxFiles: Maximum total entries to show.
  ///   - highlightFiles: Set of relative paths to highlight (e.g., modified files).
  ///   - extensions: File extensions to include (nil = all non-ignored).
  public func render(
    maxDepth: Int = 4,
    maxFiles: Int = 60,
    highlightFiles: Set<String> = [],
    extensions: [String]? = nil
  ) -> String {
    let tree = buildTree(maxDepth: maxDepth, maxFiles: maxFiles, extensions: extensions)
    return renderNode(tree, prefix: "", isLast: true, highlightFiles: highlightFiles)
  }

  /// Render a compact single-line summary (for prompt injection).
  public func summary(maxFiles: Int = 20) -> String {
    let ft = FileTools(workingDirectory: workingDirectory)
    let files = ft.listFiles(maxFiles: maxFiles)
    let dirs = Set(files.compactMap { path -> String? in
      let components = path.components(separatedBy: "/")
      return components.count > 1 ? components.first : nil
    }).sorted()

    var parts: [String] = []
    for dir in dirs {
      let count = files.filter { $0.hasPrefix(dir + "/") }.count
      parts.append("\(dir)/ (\(count))")
    }
    let rootCount = files.filter { !$0.contains("/") }.count
    if rootCount > 0 { parts.append("(\(rootCount) root files)") }
    return parts.joined(separator: "  ")
  }

  // MARK: - Tree Building

  private struct TreeNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [TreeNode]
  }

  private func buildTree(maxDepth: Int, maxFiles: Int, extensions: [String]?) -> TreeNode {
    let fm = FileManager.default
    var root = TreeNode(
      name: (workingDirectory as NSString).lastPathComponent,
      path: "", isDirectory: true, children: []
    )

    guard let enumerator = fm.enumerator(
      at: URL(fileURLWithPath: workingDirectory),
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return root }

    let baseURL = URL(fileURLWithPath: workingDirectory).standardizedFileURL
    let basePath = baseURL.path
    var count = 0

    while let url = enumerator.nextObject() as? URL, count < maxFiles {
      let stdPath = url.standardizedFileURL.path
      let rel: String
      if stdPath.hasPrefix(basePath + "/") {
        rel = String(stdPath.dropFirst(basePath.count + 1))
      } else {
        continue
      }

      let depth = rel.components(separatedBy: "/").count
      if depth > maxDepth {
        enumerator.skipDescendants()
        continue
      }

      if ignoreFilter.shouldIgnore(rel) {
        enumerator.skipDescendants()
        continue
      }

      var isDir: ObjCBool = false
      fm.fileExists(atPath: stdPath, isDirectory: &isDir)

      if isDir.boolValue {
        insertNode(&root, path: rel, name: (rel as NSString).lastPathComponent, isDirectory: true)
      } else {
        if let exts = extensions {
          let ext = (rel as NSString).pathExtension
          guard exts.contains(ext) else { continue }
        }
        insertNode(&root, path: rel, name: (rel as NSString).lastPathComponent, isDirectory: false)
        count += 1
      }
    }

    sortTree(&root)
    return root
  }

  private func insertNode(_ root: inout TreeNode, path: String, name: String, isDirectory: Bool) {
    let components = path.components(separatedBy: "/")

    if components.count == 1 {
      root.children.append(TreeNode(name: name, path: path, isDirectory: isDirectory, children: []))
      return
    }

    let dirName = components[0]
    if let idx = root.children.firstIndex(where: { $0.name == dirName && $0.isDirectory }) {
      let subPath = components.dropFirst().joined(separator: "/")
      insertNode(&root.children[idx], path: subPath, name: name, isDirectory: isDirectory)
    } else {
      var dirNode = TreeNode(name: dirName, path: dirName, isDirectory: true, children: [])
      let subPath = components.dropFirst().joined(separator: "/")
      insertNode(&dirNode, path: subPath, name: name, isDirectory: isDirectory)
      root.children.append(dirNode)
    }
  }

  private func sortTree(_ node: inout TreeNode) {
    node.children.sort { a, b in
      if a.isDirectory != b.isDirectory { return a.isDirectory }
      return a.name.lowercased() < b.name.lowercased()
    }
    for i in node.children.indices {
      sortTree(&node.children[i])
    }
  }

  // MARK: - Rendering

  private func renderNode(
    _ node: TreeNode, prefix: String, isLast: Bool,
    highlightFiles: Set<String>, isRoot: Bool = true
  ) -> String {
    var lines: [String] = []

    let connector = isRoot ? "" : (isLast ? "\u{2514}\u{2500} " : "\u{251C}\u{2500} ")
    let icon = node.isDirectory ? Style.blue("\(node.name)/") : node.name
    let highlighted = highlightFiles.contains(node.path)
    let styledName = highlighted ? Style.yellow(icon) : icon

    if isRoot {
      lines.append(Style.bold(node.name) + "/")
    } else {
      lines.append(prefix + connector + styledName)
    }

    let childPrefix = isRoot ? "" : prefix + (isLast ? "    " : "\u{2502}   ")

    for (i, child) in node.children.enumerated() {
      let childIsLast = i == node.children.count - 1
      lines.append(renderNode(
        child, prefix: childPrefix, isLast: childIsLast,
        highlightFiles: highlightFiles, isRoot: false
      ))
    }

    return lines.joined(separator: "\n")
  }
}
