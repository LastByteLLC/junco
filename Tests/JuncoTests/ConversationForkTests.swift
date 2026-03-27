// ConversationForkTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("ConversationFork")
struct ConversationForkTests {
  @Test("fork creates a fork point")
  func createFork() async {
    let dir = NSTemporaryDirectory() + "junco-fork-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let forker = ConversationForker(workingDirectory: dir)
    let point = await forker.fork(query: "try a different approach", turnIndex: 3)

    #expect(point.query == "try a different approach")
    #expect(point.turnIndex == 3)
    #expect(point.id.count == 6)
    let depth = await forker.forkDepth
    #expect(depth == 1)
  }

  @Test("unfork returns the last fork point")
  func unfork() async {
    let dir = NSTemporaryDirectory() + "junco-fork-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let forker = ConversationForker(workingDirectory: dir)
    let point = await forker.fork(query: "first fork", turnIndex: 1)
    let restored = await forker.unfork()

    #expect(restored?.id == point.id)
    let depth = await forker.forkDepth
    #expect(depth == 0)
  }

  @Test("unfork returns nil when no forks exist")
  func unforkEmpty() async {
    let forker = ConversationForker(workingDirectory: NSTemporaryDirectory())
    let result = await forker.unfork()
    #expect(result == nil)
  }

  @Test("fork stack is LIFO")
  func forkStack() async {
    let dir = NSTemporaryDirectory() + "junco-fork-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let forker = ConversationForker(workingDirectory: dir)
    _ = await forker.fork(query: "first", turnIndex: 1)
    let second = await forker.fork(query: "second", turnIndex: 2)

    let depth = await forker.forkDepth
    #expect(depth == 2)

    let restored = await forker.unfork()
    #expect(restored?.id == second.id)  // LIFO: second comes out first
  }

  @Test("ForkPoint captures timestamp")
  func forkTimestamp() {
    let point = ForkPoint(query: "test", turnIndex: 0)
    #expect(Date().timeIntervalSince(point.timestamp) < 1)
  }
}
