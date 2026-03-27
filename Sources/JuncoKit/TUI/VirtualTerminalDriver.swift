// VirtualTerminalDriver.swift — Mock terminal for testing TUI components
//
// Simulates a terminal by accepting injected keystrokes and capturing
// all output writes. Used by tests to verify LineEditor, completions,
// and rendering without a real terminal.

import Foundation

/// A mock terminal driver that replays key sequences and captures output.
public final class VirtualTerminalDriver: @unchecked Sendable, TerminalIO {
  private var keyQueue: [Key] = []
  private var keyIndex = 0
  private var outputBuffer: String = ""

  /// All text that was written to the virtual terminal.
  public var output: String { outputBuffer }

  /// Lines of output (split by newline).
  public var outputLines: [String] { outputBuffer.components(separatedBy: "\n") }

  /// The visible text on the current "screen" (ANSI codes stripped).
  public var visibleOutput: String {
    outputBuffer.replacingOccurrences(
      of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression
    )
    .replacingOccurrences(of: "\r", with: "")
  }

  public let screenWidth: Int
  public let screenHeight: Int

  public init(keys: [Key] = [], screenWidth: Int = 80, screenHeight: Int = 24) {
    self.keyQueue = keys
    self.screenWidth = screenWidth
    self.screenHeight = screenHeight
  }

  /// Inject additional keys.
  public func injectKeys(_ keys: [Key]) {
    keyQueue.append(contentsOf: keys)
  }

  /// Read the next injected key. Returns .eof when queue is exhausted.
  public func readKey() -> Key {
    guard keyIndex < keyQueue.count else { return .eof }
    let key = keyQueue[keyIndex]
    keyIndex += 1
    return key
  }

  /// Write text to the virtual output buffer.
  public func write(_ text: String) {
    outputBuffer += text
  }

  /// Flush (no-op for virtual driver).
  public func flush() {}

  /// Cursor control (captured as markers in output).
  public func beginRedraw() {
    write("\r")
    // Simulate clearing to end of screen
    outputBuffer += "[CLEAR]"
  }

  public func moveTo(column: Int) {
    // No-op for testing — cursor position is implicit in output
  }

  public func moveUp(_ n: Int = 1) {}
  public func moveDown(_ n: Int = 1) {}
  public func clearToEndOfScreen() { outputBuffer += "[CLEAR]" }
  public func clearLine() { outputBuffer += "[CLR]" }
  public func newline() { outputBuffer += "\n" }

  /// Reset for a new test.
  public func reset() {
    keyQueue.removeAll()
    keyIndex = 0
    outputBuffer = ""
  }
}
