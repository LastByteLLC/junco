// ModelPreference.swift — Persist the user's preferred model backend

import Foundation

/// Reads and writes the user's preferred model backend to ~/.junco/model.
/// Format is a single line: "afm", "ollama:modelname", etc.
public struct ModelPreference: Sendable {

  private static var filePath: String {
    (Config.globalDir as NSString).appendingPathComponent("model")
  }

  /// Read the saved preference, or nil if none.
  public static func load() -> String? {
    guard let data = FileManager.default.contents(atPath: filePath),
          let text = String(data: data, encoding: .utf8) else {
      return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Save a model preference (e.g., "afm", "ollama:gemma4:e2b-it-q4_K_M").
  public static func save(_ spec: String) {
    let dir = Config.globalDir
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? spec.write(toFile: filePath, atomically: true, encoding: .utf8)
  }

  /// Clear the saved preference (revert to auto-detect).
  public static func clear() {
    try? FileManager.default.removeItem(atPath: filePath)
  }
}
