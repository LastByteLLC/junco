// PatchApplier.swift — Apply unified diffs to files
//
// More robust than exact find/replace. Parses unified diff format
// and applies changes with line-level matching. Falls back to
// context-aware matching if exact line numbers don't match.

import Foundation

/// Errors from patch application.
public enum PatchError: Error, Sendable {
  case parseFailed(String)
  case hunkFailed(line: Int, expected: String)
  case fileNotFound(String)
}

/// Applies unified diffs to files.
public struct PatchApplier: Sendable {
  private let files: FileTools

  public init(workingDirectory: String) {
    self.files = FileTools(workingDirectory: workingDirectory)
  }

  /// Apply a unified diff to a file.
  public func apply(patch: String, to path: String) throws {
    let resolved = try files.resolve(path)
    guard FileManager.default.fileExists(atPath: resolved) else {
      throw PatchError.fileNotFound(path)
    }

    var lines = try String(contentsOfFile: resolved, encoding: .utf8)
      .components(separatedBy: "\n")

    let hunks = parseHunks(patch)
    guard !hunks.isEmpty else {
      throw PatchError.parseFailed("No hunks found in patch")
    }

    // Apply hunks in reverse order (so line numbers remain valid)
    for hunk in hunks.reversed() {
      lines = try applyHunk(hunk, to: lines)
    }

    let result = lines.joined(separator: "\n")
    try result.write(toFile: resolved, atomically: true, encoding: .utf8)
  }

  // MARK: - Hunk Parsing

  private struct Hunk {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [PatchLine]
  }

  private enum PatchLine {
    case context(String)
    case remove(String)
    case add(String)
  }

  private func parseHunks(_ patch: String) -> [Hunk] {
    var hunks: [Hunk] = []
    let patchLines = patch.components(separatedBy: "\n")
    var i = 0

    while i < patchLines.count {
      let line = patchLines[i]

      // Parse hunk header: @@ -old,count +new,count @@
      if line.hasPrefix("@@") {
        if let header = parseHunkHeader(line) {
          var hunkLines: [PatchLine] = []
          i += 1

          while i < patchLines.count && !patchLines[i].hasPrefix("@@") && !patchLines[i].hasPrefix("diff ") {
            let pl = patchLines[i]
            if pl.hasPrefix("-") {
              hunkLines.append(.remove(String(pl.dropFirst())))
            } else if pl.hasPrefix("+") {
              hunkLines.append(.add(String(pl.dropFirst())))
            } else if pl.hasPrefix(" ") {
              hunkLines.append(.context(String(pl.dropFirst())))
            } else if !pl.isEmpty {
              hunkLines.append(.context(pl))
            }
            i += 1
          }

          hunks.append(Hunk(
            oldStart: header.0, oldCount: header.1,
            newStart: header.2, newCount: header.3,
            lines: hunkLines
          ))
          continue
        }
      }
      i += 1
    }

    return hunks
  }

  private func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
    // @@ -1,5 +1,7 @@
    let pattern = /@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/
    guard let match = line.firstMatch(of: pattern) else { return nil }
    let oldStart = Int(match.1) ?? 1
    let oldCount = match.2.map { Int($0) ?? 1 } ?? 1
    let newStart = Int(match.3) ?? 1
    let newCount = match.4.map { Int($0) ?? 1 } ?? 1
    return (oldStart, oldCount, newStart, newCount)
  }

  // MARK: - Hunk Application

  private func applyHunk(_ hunk: Hunk, to lines: [String]) throws -> [String] {
    let startIdx = hunk.oldStart - 1  // 0-based

    // Try exact application first
    if let applied = tryExactApply(hunk, to: lines, at: startIdx) {
      return applied
    }

    // Fallback: context-aware search (look for context lines nearby)
    if let offset = findContextMatch(hunk, in: lines, near: startIdx) {
      if let applied = tryExactApply(hunk, to: lines, at: offset) {
        return applied
      }
    }

    throw PatchError.hunkFailed(line: hunk.oldStart, expected: "context match failed")
  }

  private func tryExactApply(_ hunk: Hunk, to lines: [String], at offset: Int) -> [String]? {
    var readPos = offset
    var newLines: [String] = []

    // Collect lines before the hunk
    newLines.append(contentsOf: lines[0..<min(offset, lines.count)])

    for patchLine in hunk.lines {
      switch patchLine {
      case .context(let text):
        guard readPos < lines.count else { return nil }
        if lines[readPos].trimmingCharacters(in: .whitespaces) != text.trimmingCharacters(in: .whitespaces) {
          return nil
        }
        newLines.append(lines[readPos])
        readPos += 1

      case .remove(let text):
        guard readPos < lines.count else { return nil }
        if lines[readPos].trimmingCharacters(in: .whitespaces) != text.trimmingCharacters(in: .whitespaces) {
          return nil
        }
        readPos += 1  // Skip this line (removed)

      case .add(let text):
        newLines.append(text)
      }
    }

    // Append remaining lines
    if readPos < lines.count {
      newLines.append(contentsOf: lines[readPos...])
    }

    return newLines
  }

  private func findContextMatch(_ hunk: Hunk, in lines: [String], near center: Int) -> Int? {
    // Look for the first context line within ±20 lines of expected position
    guard let firstContext = hunk.lines.first(where: {
      if case .context = $0 { return true }; return false
    }) else { return nil }

    guard case .context(let searchText) = firstContext else { return nil }
    let trimmed = searchText.trimmingCharacters(in: .whitespaces)

    let searchRange = max(0, center - 20)..<min(lines.count, center + 20)
    for i in searchRange {
      if lines[i].trimmingCharacters(in: .whitespaces) == trimmed {
        return i
      }
    }
    return nil
  }
}
