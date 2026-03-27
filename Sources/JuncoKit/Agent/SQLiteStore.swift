// SQLiteStore.swift — SQLite-backed persistence for reflections and metadata
//
// Stored in ~/.junco/junco.db (global).
// Uses parameterized queries throughout to prevent SQL injection.
// Uses the system sqlite3 C library — no external dependencies.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed key-value and reflection store.
public final class SQLiteStore: @unchecked Sendable {
  private var db: OpaquePointer?
  public let path: String

  public init(path: String? = nil) {
    self.path = path ?? Self.defaultPath()
    open()
    createTables()
  }

  deinit {
    if db != nil { sqlite3_close(db) }
  }

  private static func defaultPath() -> String {
    try? FileManager.default.createDirectory(atPath: Config.globalDir, withIntermediateDirectories: true)
    return (Config.globalDir as NSString).appendingPathComponent("junco.db")
  }

  private func open() {
    sqlite3_open(path, &db)
  }

  private func createTables() {
    exec("""
      CREATE TABLE IF NOT EXISTS reflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL,
        query TEXT NOT NULL,
        task_summary TEXT,
        insight TEXT,
        improvement TEXT,
        succeeded INTEGER,
        created_at TEXT DEFAULT (datetime('now'))
      )
    """)
    exec("CREATE INDEX IF NOT EXISTS idx_reflections_project ON reflections(project)")
    exec("""
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT (datetime('now'))
      )
    """)
    exec("""
      CREATE VIRTUAL TABLE IF NOT EXISTS reflections_fts USING fts5(
        query, task_summary, insight, improvement,
        content=reflections, content_rowid=id
      )
    """)
  }

  // MARK: - Reflections (all parameterized)

  public func saveReflection(project: String, query: String, reflection: AgentReflection) {
    let sql = "INSERT INTO reflections (project, query, task_summary, insight, improvement, succeeded) VALUES (?, ?, ?, ?, ?, ?)"
    guard let stmt = prepare(sql) else { return }
    defer { sqlite3_finalize(stmt) }

    bind(stmt, 1, project)
    bind(stmt, 2, query)
    bind(stmt, 3, reflection.taskSummary)
    bind(stmt, 4, reflection.insight)
    bind(stmt, 5, reflection.improvement)
    sqlite3_bind_int(stmt, 6, reflection.succeeded ? 1 : 0)
    sqlite3_step(stmt)

    // Update FTS index (also parameterized)
    let rowId = sqlite3_last_insert_rowid(db)
    let ftsSql = "INSERT INTO reflections_fts (rowid, query, task_summary, insight, improvement) VALUES (?, ?, ?, ?, ?)"
    guard let ftsStmt = prepare(ftsSql) else { return }
    defer { sqlite3_finalize(ftsStmt) }
    sqlite3_bind_int64(ftsStmt, 1, rowId)
    bind(ftsStmt, 2, query)
    bind(ftsStmt, 3, reflection.taskSummary)
    bind(ftsStmt, 4, reflection.insight)
    bind(ftsStmt, 5, reflection.improvement)
    sqlite3_step(ftsStmt)
  }

  public func searchReflections(query: String, project: String, limit: Int = 5) -> [(String, String)] {
    let sql = "SELECT r.insight, r.improvement FROM reflections r JOIN reflections_fts f ON r.id = f.rowid WHERE reflections_fts MATCH ? AND r.project = ? ORDER BY rank LIMIT ?"
    guard let stmt = prepare(sql) else { return [] }
    defer { sqlite3_finalize(stmt) }

    bind(stmt, 1, query)
    bind(stmt, 2, project)
    sqlite3_bind_int(stmt, 3, Int32(limit))

    var results: [(String, String)] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let insight = columnText(stmt, 0)
      let improvement = columnText(stmt, 1)
      results.append((insight, improvement))
    }
    return results
  }

  public func reflectionCount(project: String) -> Int {
    let sql = "SELECT COUNT(*) FROM reflections WHERE project = ?"
    guard let stmt = prepare(sql) else { return 0 }
    defer { sqlite3_finalize(stmt) }
    bind(stmt, 1, project)
    return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
  }

  // MARK: - Metadata (parameterized)

  public func setMetadata(key: String, value: String) {
    let sql = "INSERT OR REPLACE INTO metadata (key, value, updated_at) VALUES (?, ?, datetime('now'))"
    guard let stmt = prepare(sql) else { return }
    defer { sqlite3_finalize(stmt) }
    bind(stmt, 1, key)
    bind(stmt, 2, value)
    sqlite3_step(stmt)
  }

  public func getMetadata(key: String) -> String? {
    let sql = "SELECT value FROM metadata WHERE key = ?"
    guard let stmt = prepare(sql) else { return nil }
    defer { sqlite3_finalize(stmt) }
    bind(stmt, 1, key)
    return sqlite3_step(stmt) == SQLITE_ROW ? columnText(stmt, 0) : nil
  }

  // MARK: - Helpers

  private func prepare(_ sql: String) -> OpaquePointer? {
    var stmt: OpaquePointer?
    return sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK ? stmt : nil
  }

  private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
  }

  private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
    guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: cStr)
  }

  @discardableResult
  private func exec(_ sql: String) -> Bool {
    sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
  }
}
