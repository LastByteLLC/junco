// TreeSitterRepairTests.swift — Tests for AST-guided structural repair

import Foundation
import Testing
@testable import JuncoKit

@Suite("TreeSitterRepair")
struct TreeSitterRepairTests {

  let repair = TreeSitterRepair()

  // MARK: - Clean Input (no-op)

  @Test("Clean code passes through unchanged")
  func cleanCodeNoOp() {
    let code = """
      import Foundation

      struct Podcast: Codable, Identifiable {
          var id = UUID()
          var name: String
      }

      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.isEmpty)
    #expect(result == code)
  }

  // MARK: - Strip Leading Prose

  @Test("Strip leading prose before import")
  func stripLeadingProse() {
    let code = """
      Here is the Swift code you requested:

      import SwiftUI

      struct ContentView: View {
          var body: some View {
              Text("Hello")
          }
      }
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("stripped leading prose"))
    #expect(result.hasPrefix("import SwiftUI"))
    #expect(!result.contains("Here is the Swift"))
  }

  @Test("Strip multi-line prose before code")
  func stripMultiLineProse() {
    let code = """
      Below is the implementation.
      This creates a simple model type.

      struct Item: Identifiable {
          var id = UUID()
      }
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("stripped leading prose"))
    #expect(result.hasPrefix("struct Item"))
  }

  @Test("Preserve leading comments")
  func preserveLeadingComments() {
    let code = """
      // MARK: - Models

      struct Item: Identifiable {
          var id = UUID()
      }
      """
    let (result, fixes) = repair.repair(code)
    #expect(!fixes.contains("stripped leading prose"))
    #expect(result.contains("// MARK:"))
  }

  // MARK: - Strip Trailing Junk

  @Test("Strip trailing prose after code")
  func stripTrailingJunk() {
    let code = """
      import Foundation

      struct Item {
          var name: String
      }

      This completes the implementation.
      Let me know if you need changes.
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("stripped trailing junk"))
    #expect(!result.contains("This completes"))
    #expect(result.contains("struct Item"))
  }

  // MARK: - Balance Braces

  @Test("Append one missing closing brace")
  func missingOneBrace() {
    let code = """
      struct Foo {
          func bar() {
              print("hello")
          }
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("balanced braces"))
    // Count braces in result
    let opens = result.filter { $0 == "{" }.count
    let closes = result.filter { $0 == "}" }.count
    #expect(opens == closes)
  }

  @Test("Append two missing closing braces")
  func missingTwoBraces() {
    let code = """
      struct Foo {
          func bar() {
              print("hello")
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("balanced braces"))
    let opens = result.filter { $0 == "{" }.count
    let closes = result.filter { $0 == "}" }.count
    #expect(opens == closes)
  }

  @Test("Remove extra trailing braces")
  func extraTrailingBraces() {
    let code = """
      struct Foo {
          var x: Int
      }
      }
      }
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("balanced braces"))
    let opens = result.filter { $0 == "{" }.count
    let closes = result.filter { $0 == "}" }.count
    #expect(opens == closes)
  }

  @Test("Already balanced braces are unchanged")
  func balancedBraces() {
    let code = """
      struct Foo {
          func bar() {
              print("hello")
          }
      }
      """
    let result = repair.balanceBraces(code)
    #expect(result == code)
  }

  // MARK: - Unterminated Strings

  @Test("Close unterminated string literal")
  func unterminatedString() {
    let code = """
      let greeting = "hello
      let x = 42
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("closed unterminated string"))
    // The first line should now have a closing quote
    let firstLine = result.components(separatedBy: "\n").first ?? ""
    let quoteCount = firstLine.filter { $0 == "\"" }.count
    #expect(quoteCount % 2 == 0)
  }

  // MARK: - Combined Defects

  @Test("Fix prose + missing brace together")
  func combinedProseAndBrace() {
    let code = """
      Here's your code:

      import SwiftUI

      struct ContentView: View {
          var body: some View {
              Text("Hello")
          }
      """
    let (result, fixes) = repair.repair(code)
    #expect(fixes.contains("stripped leading prose"))
    #expect(fixes.contains("balanced braces"))
    #expect(result.hasPrefix("import SwiftUI"))
    let opens = result.filter { $0 == "{" }.count
    let closes = result.filter { $0 == "}" }.count
    #expect(opens == closes)
  }

  @Test("Fix trailing junk + extra braces")
  func combinedTrailingAndBraces() {
    let code = """
      struct Foo {
          var x: Int
      }
      }
      That's the implementation.
      """
    let (result, fixes) = repair.repair(code)
    #expect(!result.contains("That's the"))
    let opens = result.filter { $0 == "{" }.count
    let closes = result.filter { $0 == "}" }.count
    #expect(opens == closes)
  }

  // MARK: - Individual Pass Tests

  @Test("stripLeadingProse with @Observable attribute")
  func stripProseBeforeAttribute() {
    let code = """
      This is the ViewModel:

      @Observable
      class PodcastViewModel {
          var items: [String] = []
      }
      """
    let result = repair.stripLeadingProse(code)
    #expect(!result.contains("This is the"))
    #expect(result.contains("@Observable"))
  }

  @Test("balanceBraces ignores braces in strings")
  func bracesInStrings() {
    let code = """
      let json = "{\\"key\\": \\"value\\"}"
      let x = 1
      """
    let result = repair.balanceBraces(code)
    // Should not be modified — braces are inside a string
    #expect(result == code)
  }

  @Test("Deeply missing braces (>3) left unchanged")
  func tooManyMissing() {
    let code = """
      struct A {
          struct B {
              struct C {
                  func d() {
                      print("deep")
      """
    let result = repair.balanceBraces(code)
    // 4 missing braces — too many, should return original
    #expect(result == code)
  }

  @Test("Empty input returns empty")
  func emptyInput() {
    let (result, fixes) = repair.repair("")
    #expect(result.isEmpty)
    #expect(fixes.isEmpty)
  }
}
