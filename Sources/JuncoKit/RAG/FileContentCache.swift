// FileContentCache.swift — In-memory LRU cache for file contents
//
// Avoids re-reading hot files during interactive search sessions.
// Invalidated by FileWatcher change events.
// Memory: ~500KB for 50 files at 10KB avg.

import Foundation

/// Actor-based LRU file content cache.
/// Caches file contents with modification timestamps for validation.
public actor FileContentCache {
  private var cache: [String: CacheEntry] = [:]
  private var accessOrder: [String] = []
  private let maxEntries: Int

  struct CacheEntry {
    let content: String
    let modified: Date
    let tokenEstimate: Int
  }

  public init(maxEntries: Int = 100) {
    self.maxEntries = maxEntries
  }

  /// Get cached content if available and not stale.
  public func get(_ path: String, maxTokens: Int) -> String? {
    guard let entry = cache[path] else { return nil }

    // Validate modification time
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: path),
          let modified = attrs[.modificationDate] as? Date,
          modified <= entry.modified
    else {
      // File changed — invalidate
      cache.removeValue(forKey: path)
      return nil
    }

    // Check token budget
    if entry.tokenEstimate > maxTokens {
      return nil  // Caller needs a different budget
    }

    // Update access order for LRU
    if let idx = accessOrder.firstIndex(of: path) {
      accessOrder.remove(at: idx)
    }
    accessOrder.append(path)

    return entry.content
  }

  /// Cache file content.
  public func set(_ path: String, content: String) {
    // Evict LRU if at capacity
    while cache.count >= maxEntries, let oldest = accessOrder.first {
      cache.removeValue(forKey: oldest)
      accessOrder.removeFirst()
    }

    let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date()

    cache[path] = CacheEntry(
      content: content,
      modified: modified,
      tokenEstimate: TokenBudget.estimate(content)
    )
    accessOrder.append(path)
  }

  /// Invalidate a specific file (called by FileWatcher on changes).
  public func invalidate(_ path: String) {
    cache.removeValue(forKey: path)
    accessOrder.removeAll { $0 == path }
  }

  /// Clear entire cache.
  public func clear() {
    cache.removeAll()
    accessOrder.removeAll()
  }

  /// Number of cached files.
  public var count: Int { cache.count }
}
