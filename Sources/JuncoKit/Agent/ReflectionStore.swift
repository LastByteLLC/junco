// ReflectionStore.swift — Persistent storage and retrieval of task reflections
//
// Stores reflections as JSONL in .junco/reflections.jsonl per project.
// Retrieves relevant reflections via keyword matching against new queries.
// Auto-compacts when the store exceeds a threshold.

import Foundation

/// A stored reflection with timestamp and query context.
public struct StoredReflection: Codable, Sendable {
  public let timestamp: Date
  public let query: String
  public let reflection: AgentReflection

  public init(query: String, reflection: AgentReflection) {
    self.timestamp = Date()
    self.query = query
    self.reflection = reflection
  }
}

/// Manages persistent reflection storage for the reflexion loop.
public struct ReflectionStore: Sendable {
  private let storePath: String
  private let maxEntries: Int

  public init(projectDirectory: String, maxEntries: Int = 100) {
    let juncoDir = (projectDirectory as NSString).appendingPathComponent(".junco")
    self.storePath = (juncoDir as NSString).appendingPathComponent("reflections.jsonl")
    self.maxEntries = maxEntries

    // Ensure directory exists
    try? FileManager.default.createDirectory(
      atPath: juncoDir, withIntermediateDirectories: true
    )
  }

  // MARK: - Save

  /// Append a reflection to the store.
  public func save(query: String, reflection: AgentReflection) throws {
    let entry = StoredReflection(query: query, reflection: reflection)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(entry)
    guard var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"

    if FileManager.default.fileExists(atPath: storePath) {
      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: storePath))
      handle.seekToEndOfFile()
      handle.write(line.data(using: .utf8)!)
      handle.closeFile()
    } else {
      try line.write(toFile: storePath, atomically: true, encoding: .utf8)
    }

    // Auto-compact if needed
    try autoCompact()
  }

  // MARK: - Retrieve

  /// Find reflections relevant to a query, scored by keyword overlap.
  /// Returns up to `limit` reflections, most relevant first.
  public func retrieve(query: String, limit: Int = 3) -> [StoredReflection] {
    guard let entries = loadAll() else { return [] }

    let queryTerms = tokenize(query)

    var scored: [(entry: StoredReflection, score: Double)] = entries.map { entry in
      let entryTerms = tokenize(
        entry.query + " " + entry.reflection.taskSummary + " " + entry.reflection.insight
      )
      let overlap = queryTerms.intersection(entryTerms).count
      let recencyBonus = min(1.0, 7.0 / max(1, -entry.timestamp.timeIntervalSinceNow / 86400))
      return (entry, Double(overlap) + recencyBonus * 0.5)
    }

    scored.sort { $0.score > $1.score }
    return scored.prefix(limit).filter { $0.score > 0 }.map(\.entry)
  }

  /// Format retrieved reflections for prompt injection.
  /// Target: ~100 tokens.
  public func formatForPrompt(query: String) -> String? {
    let relevant = retrieve(query: query, limit: 2)
    guard !relevant.isEmpty else { return nil }

    let lines = relevant.map { entry in
      "- \(entry.reflection.insight) → \(entry.reflection.improvement)"
    }
    return "Past experience:\n" + lines.joined(separator: "\n")
  }

  // MARK: - Load

  private func loadAll() -> [StoredReflection]? {
    guard FileManager.default.fileExists(atPath: storePath),
          let data = FileManager.default.contents(atPath: storePath),
          let content = String(data: data, encoding: .utf8)
    else { return nil }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return content.split(separator: "\n").compactMap { line in
      guard let lineData = line.data(using: .utf8) else { return nil }
      return try? decoder.decode(StoredReflection.self, from: lineData)
    }
  }

  // MARK: - Auto-Compact

  /// Keep only the most recent `maxEntries` reflections.
  private func autoCompact() throws {
    guard let entries = loadAll(), entries.count > maxEntries else { return }

    let kept = Array(entries.suffix(maxEntries))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let lines = kept.compactMap { entry -> String? in
      guard let data = try? encoder.encode(entry),
            let line = String(data: data, encoding: .utf8)
      else { return nil }
      return line
    }

    try lines.joined(separator: "\n").appending("\n")
      .write(toFile: storePath, atomically: true, encoding: .utf8)
  }

  // MARK: - Stats

  /// Number of stored reflections.
  public var count: Int {
    loadAll()?.count ?? 0
  }

  private func tokenize(_ text: String) -> Set<String> {
    Set(
      text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 2 }
    )
  }
}
