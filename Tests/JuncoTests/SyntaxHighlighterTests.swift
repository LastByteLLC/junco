// SyntaxHighlighterTests.swift

import Testing
@testable import JuncoKit

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
  let highlighter = SyntaxHighlighter()

  @Test("Swift keywords are highlighted")
  func swiftKeywords() {
    let code = "func hello() { let x = 1 }"
    let result = highlighter.highlight(code, language: "swift")
    // Should contain ANSI escape codes for keywords
    #expect(result.contains("\u{1B}["))
    // Original text preserved (just with escape codes added)
    #expect(result.contains("hello"))
    #expect(result.contains("func"))
  }

  @Test("XML/plist tags are highlighted")
  func xmlTags() {
    let code = "<dict><key>CFBundleName</key><string>MyApp</string></dict>"
    let result = highlighter.highlight(code, language: "plist")
    #expect(result.contains("\u{1B}["))
    #expect(result.contains("dict"))
  }

  @Test("JSON keys are highlighted")
  func jsonKeys() {
    let code = "{\"name\": \"junco\", \"version\": 1}"
    let result = highlighter.highlight(code, language: "json")
    #expect(result.contains("\u{1B}["))
    #expect(result.contains("name"))
  }

  @Test("bash variables are highlighted")
  func bashVars() {
    let code = "echo $HOME && export PATH=/usr/bin"
    let result = highlighter.highlight(code, language: "bash")
    #expect(result.contains("\u{1B}["))
    #expect(result.contains("$HOME"))
  }

  @Test("unknown language uses generic highlighting")
  func unknown() {
    let code = "x = 42 // comment"
    let result = highlighter.highlight(code, language: "unknown")
    #expect(result.contains("\u{1B}["))
  }

  @Test("strings are green")
  func strings() {
    let code = "let s = \"hello world\""
    let result = highlighter.highlight(code, language: "swift")
    // Green is ANSI code 32
    #expect(result.contains("\u{1B}[32m"))
  }

  @Test("comments are dim")
  func comments() {
    let code = "// this is a comment\nlet x = 1"
    let result = highlighter.highlight(code, language: "swift")
    // Dim is ANSI code 2
    #expect(result.contains("\u{1B}[2m"))
  }
}
