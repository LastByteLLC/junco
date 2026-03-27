// FileTools.swift — Validated file operations with path safety

import Foundation

/// Errors from file operations.
public enum FileToolError: Error, Sendable {
  case pathOutsideProject(String)
  case fileNotFound(String)
  case editTextNotFound(path: String, snippet: String)
  case writeBlocked(String)
}

/// Safe file operations that validate paths stay within the project directory.
public struct FileTools: Sendable {
  public let workingDirectory: String

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
  }

  // MARK: - Path Validation

  /// Resolve a possibly-relative path and verify it's within the working directory.
  public func resolve(_ path: String) throws -> String {
    let resolved: String
    if path.hasPrefix("/") {
      resolved = path
    } else {
      resolved = (workingDirectory as NSString).appendingPathComponent(path)
    }

    // Resolve symlinks fully to prevent path traversal via symlink chains
    let normalized = URL(fileURLWithPath: resolved).standardizedFileURL.path
    let normalizedWD = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path

    guard normalized.hasPrefix(normalizedWD) else {
      throw FileToolError.pathOutsideProject(path)
    }

    return normalized
  }

  // MARK: - Read

  /// Read a file, returning its content truncated to fit a token budget.
  public func read(path: String, maxTokens: Int = 800) throws -> String {
    let resolved = try resolve(path)
    guard FileManager.default.fileExists(atPath: resolved) else {
      throw FileToolError.fileNotFound(path)
    }
    let content = try String(contentsOfFile: resolved, encoding: .utf8)
    return TokenBudget.truncate(content, toTokens: maxTokens)
  }

  /// Check if a file exists.
  public func exists(_ path: String) -> Bool {
    guard let resolved = try? resolve(path) else { return false }
    return FileManager.default.fileExists(atPath: resolved)
  }

  // MARK: - Write

  /// Write content to a file, creating parent directories as needed.
  public func write(path: String, content: String) throws {
    let resolved = try resolve(path)

    // Block writing to sensitive locations (uses consolidated config)
    let name = (resolved as NSString).lastPathComponent
    if Config.sensitiveFilePatterns.contains(where: { name.contains($0) }) {
      throw FileToolError.writeBlocked("Refusing to write to sensitive file: \(name)")
    }

    let dir = (resolved as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try content.write(toFile: resolved, atomically: true, encoding: .utf8)
  }

  // MARK: - Edit (find-replace)

  /// Find and replace text in a file. Supports fuzzy matching on retry.
  public func edit(path: String, find: String, replace: String, fuzzy: Bool = false) throws {
    let resolved = try resolve(path)
    guard FileManager.default.fileExists(atPath: resolved) else {
      throw FileToolError.fileNotFound(path)
    }

    var content = try String(contentsOfFile: resolved, encoding: .utf8)

    if content.contains(find) {
      content = content.replacingOccurrences(of: find, with: replace)
    } else if fuzzy {
      // Fuzzy: try trimmed whitespace matching
      let trimmedFind = find.trimmingCharacters(in: .whitespacesAndNewlines)
      if let range = content.range(of: trimmedFind) {
        content.replaceSubrange(range, with: replace)
      } else {
        throw FileToolError.editTextNotFound(
          path: path,
          snippet: String(find.prefix(60))
        )
      }
    } else {
      throw FileToolError.editTextNotFound(
        path: path,
        snippet: String(find.prefix(60))
      )
    }

    try content.write(toFile: resolved, atomically: true, encoding: .utf8)
  }

  // MARK: - List

  /// List files in the project matching given extensions, up to a depth.
  public func listFiles(
    extensions: [String] = ["swift", "js", "ts", "json", "md", "css", "html"],
    maxDepth: Int = 4,
    maxFiles: Int = 50
  ) -> [String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: URL(fileURLWithPath: workingDirectory),
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    var results: [String] = []
    // Resolve symlinks for consistent path comparison (macOS /tmp → /private/tmp)
    let baseURL = URL(fileURLWithPath: workingDirectory).standardizedFileURL
    let basePath = baseURL.path

    while let url = enumerator.nextObject() as? URL {
      // Depth check
      let stdPath = url.standardizedFileURL.path
      let rel: String
      if stdPath.hasPrefix(basePath + "/") {
        rel = String(stdPath.dropFirst(basePath.count + 1))
      } else {
        rel = stdPath
      }
      let depth = rel.components(separatedBy: "/").count
      if depth > maxDepth {
        enumerator.skipDescendants()
        continue
      }

      // Skip ignored directories (.juncoignore + builtins)
      let ignoreFilter = IgnoreFilter(workingDirectory: workingDirectory)
      if ignoreFilter.shouldIgnore(rel) {
        enumerator.skipDescendants()
        continue
      }

      // Extension filter
      let ext = url.pathExtension
      if extensions.contains(ext) {
        results.append(rel)
        if results.count >= maxFiles { break }
      }
    }

    return results.sorted()
  }
}
