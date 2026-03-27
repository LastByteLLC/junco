// DiffPreview.swift — Show proposed changes as unified diff before applying
//
// Generates a preview diff without modifying files.
// Used by the orchestrator to let users approve/reject edits.

import Foundation

/// Generates unified diff previews for proposed file changes.
public struct DiffPreview: Sendable {
  public init() {}

  /// Generate a unified diff string for a find-replace operation.
  public func diff(
    filePath: String,
    originalContent: String,
    find: String,
    replace: String
  ) -> String? {
    guard originalContent.contains(find) else { return nil }

    let newContent = originalContent.replacingOccurrences(of: find, with: replace)
    return unifiedDiff(
      path: filePath,
      original: originalContent,
      modified: newContent
    )
  }

  /// Generate a unified diff string for a full file write.
  public func diffWrite(
    filePath: String,
    existingContent: String?,
    newContent: String
  ) -> String {
    if let existing = existingContent {
      return unifiedDiff(path: filePath, original: existing, modified: newContent)
    } else {
      let lines = newContent.components(separatedBy: "\n")
      var output = "--- /dev/null\n+++ b/\(filePath)\n@@ -0,0 +1,\(lines.count) @@\n"
      for line in lines {
        output += "+\(line)\n"
      }
      return output
    }
  }

  /// Simple line-based unified diff.
  private func unifiedDiff(path: String, original: String, modified: String) -> String {
    let oldLines = original.components(separatedBy: "\n")
    let newLines = modified.components(separatedBy: "\n")

    var output = "--- a/\(path)\n+++ b/\(path)\n"
    var i = 0, j = 0
    var hunkLines: [String] = []
    var hunkStartOld = 0, hunkStartNew = 0

    while i < oldLines.count || j < newLines.count {
      if i < oldLines.count && j < newLines.count && oldLines[i] == newLines[j] {
        if !hunkLines.isEmpty {
          hunkLines.append(" \(oldLines[i])")
        }
        i += 1; j += 1
        continue
      }

      // Start a new hunk if needed
      if hunkLines.isEmpty {
        hunkStartOld = max(0, i - 2)
        hunkStartNew = max(0, j - 2)
        // Add context lines before
        for ctx in max(0, i - 2)..<i {
          if ctx < oldLines.count {
            hunkLines.append(" \(oldLines[ctx])")
          }
        }
      }

      // Find where lines diverge and converge
      if i < oldLines.count && (j >= newLines.count || oldLines[i] != newLines[j]) {
        hunkLines.append("-\(oldLines[i])")
        i += 1
      }
      if j < newLines.count && (i >= oldLines.count || (i > 0 && oldLines[i - 1] != newLines[j])) {
        hunkLines.append("+\(newLines[j])")
        j += 1
      }
    }

    if !hunkLines.isEmpty {
      let removals = hunkLines.filter { $0.hasPrefix("-") }.count
      let additions = hunkLines.filter { $0.hasPrefix("+") }.count
      let context = hunkLines.filter { $0.hasPrefix(" ") }.count
      output += "@@ -\(hunkStartOld + 1),\(removals + context) +\(hunkStartNew + 1),\(additions + context) @@\n"
      output += hunkLines.joined(separator: "\n") + "\n"
    }

    return output
  }
}
