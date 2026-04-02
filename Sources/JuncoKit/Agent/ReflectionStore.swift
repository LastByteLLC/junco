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

  /// Recency decay half-life in days.
  /// At 14 days, a reflection's recency bonus is halved.
  public static let recencyHalfLife: Double = 14.0

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
      // Exponential decay: half-life of 14 days.
      // 7 days: 0.61, 14 days: 0.37, 28 days: 0.14, 60 days: 0.01
      let daysSince = max(0, -entry.timestamp.timeIntervalSinceNow / 86400)
      let decayFactor = exp(-daysSince / Self.recencyHalfLife)
      return (entry, Double(overlap) * (1.0 + decayFactor))
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

  // MARK: - Auto-Compact with Distillation

  /// Distill reflections when over capacity.
  /// Instead of just keeping the last N, clusters by keyword overlap
  /// and keeps the most recent success + failure per cluster.
  private func autoCompact() throws {
    guard let entries = loadAll(), entries.count > maxEntries else { return }

    let distilled = distill(entries)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let lines = distilled.compactMap { entry -> String? in
      guard let data = try? encoder.encode(entry),
            let line = String(data: data, encoding: .utf8)
      else { return nil }
      return line
    }

    try lines.joined(separator: "\n").appending("\n")
      .write(toFile: storePath, atomically: true, encoding: .utf8)
  }

  /// Cluster reflections by keyword overlap, keep best per cluster.
  /// Returns at most `maxEntries/2` distilled entries.
  func distill(_ entries: [StoredReflection]) -> [StoredReflection] {
    guard entries.count > 3 else { return entries }

    // Simple single-pass clustering: assign each entry to a cluster
    // based on keyword overlap with existing cluster centroids.
    var clusters: [[StoredReflection]] = []

    for entry in entries {
      let terms = tokenize(entry.query + " " + entry.reflection.taskSummary)
      var bestCluster = -1
      var bestOverlap = 0

      for (i, cluster) in clusters.enumerated() {
        guard let representative = cluster.first else { continue }
        let repTerms = tokenize(representative.query + " " + representative.reflection.taskSummary)
        let overlap = terms.intersection(repTerms).count
        if overlap > bestOverlap && overlap >= 2 {
          bestOverlap = overlap
          bestCluster = i
        }
      }

      if bestCluster >= 0 {
        clusters[bestCluster].append(entry)
      } else {
        clusters.append([entry])
      }
    }

    // For each cluster, keep: most recent success + most recent failure
    var kept: [StoredReflection] = []
    for cluster in clusters {
      let successes = cluster.filter { $0.reflection.succeeded }
        .sorted { $0.timestamp > $1.timestamp }
      let failures = cluster.filter { !$0.reflection.succeeded }
        .sorted { $0.timestamp > $1.timestamp }

      if let best = successes.first { kept.append(best) }
      if let worst = failures.first { kept.append(worst) }
    }

    // Sort by recency, cap at maxEntries/2
    kept.sort { $0.timestamp > $1.timestamp }
    return Array(kept.prefix(maxEntries / 2))
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
