// LineEditorTests.swift — Tests for LineEditor using VirtualTerminalDriver

import Testing
import Foundation
@testable import JuncoKit

@Suite("LineEditor")
struct LineEditorTests {
  private func makeEditor(completers: [any CompletionProvider] = []) -> LineEditor {
    LineEditor(prompt: "> ", completers: completers)
  }

  @Test("typing and submitting returns text")
  func typeAndSubmit() {
    let vt = VirtualTerminalDriver(keys: [
      .char("h"), .char("i"), .enter,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt)
    #expect(result == "hi")
  }

  @Test("backspace deletes character")
  func backspace() {
    let vt = VirtualTerminalDriver(keys: [
      .char("a"), .char("b"), .char("c"), .backspace, .enter,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt)
    #expect(result == "ab")
  }

  @Test("ctrl-U clears line")
  func ctrlU() {
    let vt = VirtualTerminalDriver(keys: [
      .char("h"), .char("e"), .char("l"), .char("l"), .char("o"),
      .ctrlU,
      .char("b"), .char("y"), .char("e"), .enter,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt)
    #expect(result == "bye")
  }

  @Test("ctrl-C returns nil")
  func ctrlC() {
    let vt = VirtualTerminalDriver(keys: [
      .char("x"), .ctrlC,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt)
    #expect(result == nil)
  }

  @Test("empty submit returns nil")
  func emptySubmit() {
    let vt = VirtualTerminalDriver(keys: [.enter])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt)
    #expect(result == nil)
  }

  private func makeIsolatedHistory() -> (CommandHistory, String) {
    let dir = NSTemporaryDirectory() + "junco-le-hist-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return (CommandHistory(maxEntries: 100, path: "\(dir)/history"), dir)
  }

  @Test("history navigation via up/down")
  func historyNavigation() {
    let (history, dir) = makeIsolatedHistory()
    defer { try? FileManager.default.removeItem(atPath: dir) }

    history.append("first command")
    history.append("second command")

    let vt = VirtualTerminalDriver(keys: [
      .up,     // → "second command"
      .up,     // → "first command"
      .enter,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt, history: history)
    #expect(result == "first command")
  }

  @Test("history: down returns to newer entry")
  func historyDown() {
    let (history, dir) = makeIsolatedHistory()
    defer { try? FileManager.default.removeItem(atPath: dir) }

    history.append("old")
    history.append("new")

    let vt = VirtualTerminalDriver(keys: [
      .up,     // → "new"
      .up,     // → "old"
      .down,   // → "new"
      .enter,
    ])
    let editor = makeEditor()
    let result = editor.readLine(driver: vt, history: history)
    #expect(result == "new")
  }

  @Test("command completion via tab")
  func commandCompletion() {
    let vt = VirtualTerminalDriver(keys: [
      .char("/"), .char("h"), .char("e"), .tab, .enter,
    ])
    let editor = LineEditor(prompt: "> ", completers: [CommandCompleter()])
    let result = editor.readLine(driver: vt)
    #expect(result == "/help")
  }

  @Test("escape dismisses completions")
  func escapeDismiss() {
    let vt = VirtualTerminalDriver(keys: [
      .char("/"), // triggers completions
      .escape,    // dismiss
      .backspace, // remove /
      .char("h"), .char("i"), .enter,
    ])
    let editor = LineEditor(prompt: "> ", completers: [CommandCompleter()])
    let result = editor.readLine(driver: vt)
    #expect(result == "hi")
  }

  @Test("output contains prompt text")
  func outputContainsPrompt() {
    let vt = VirtualTerminalDriver(keys: [.char("x"), .enter])
    let editor = LineEditor(prompt: "test> ", completers: [])
    _ = editor.readLine(driver: vt)
    let visible = vt.visibleOutput
    #expect(visible.contains("test>"))
  }
}
