// JSCValidatorTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("JSCValidator")
struct JSCValidatorTests {
  let validator = JSCValidator()

  @Test("valid code passes")
  func validCode() {
    let result = validator.validate(code: "const x = 42; console.log(x);")
    #expect(result.valid)
    #expect(result.output == "42")
  }

  @Test("syntax error detected")
  func syntaxError() {
    let result = validator.validate(code: "function broken( { }")
    #expect(!result.valid)
    #expect(result.error?.contains("SyntaxError") == true)
  }

  @Test("runtime error detected")
  func runtimeError() {
    let result = validator.validate(code: "null.property")
    #expect(!result.valid)
    #expect(result.error?.contains("TypeError") == true)
  }

  @Test("reference error detected")
  func referenceError() {
    let result = validator.validate(code: "undeclaredVariable.foo")
    #expect(!result.valid)
  }

  @Test("test assertions pass")
  func testPass() {
    let result = validator.validate(
      code: "function add(a, b) { return a + b; }",
      testCode: "if (add(2,3) !== 5) throw new Error('wrong')"
    )
    #expect(result.valid)
  }

  @Test("test assertions fail")
  func testFail() {
    let result = validator.validate(
      code: "function add(a, b) { return a - b; }",
      testCode: "if (add(2,3) !== 5) throw new Error('expected 5, got ' + add(2,3))"
    )
    #expect(!result.valid)
    #expect(result.error?.contains("expected 5") == true)
  }

  @Test("ES6 features work")
  func es6() {
    let result = validator.validate(code: """
      const greet = (name) => `Hello, ${name}!`;
      console.log(greet('world'));
    """)
    #expect(result.valid)
    #expect(result.output == "Hello, world!")
  }

  @Test("module.exports available")
  func moduleExports() {
    let result = validator.validate(code: "module.exports = { x: 1 };")
    #expect(result.valid)
  }

  @Test("syntax-only check")
  func syntaxOnly() {
    let result = validator.checkSyntax("const x = 1; const y = x + 2;")
    #expect(result.valid)
  }

  @Test("syntax-only catches errors")
  func syntaxOnlyError() {
    let result = validator.checkSyntax("const x = {;}")
    #expect(!result.valid)
  }

  @Test("feedbackForLLM returns nil for valid JS")
  func feedbackValid() {
    let feedback = validator.feedbackForLLM(code: "const x = 1;", filePath: "test.js")
    #expect(feedback == nil)
  }

  @Test("feedbackForLLM returns error for invalid JS")
  func feedbackInvalid() {
    let feedback = validator.feedbackForLLM(code: "function({)", filePath: "test.js")
    #expect(feedback != nil)
    #expect(feedback?.contains("error") == true)
  }

  @Test("feedbackForLLM skips non-JS files")
  func feedbackSkips() {
    let feedback = validator.feedbackForLLM(code: "not js at all {{{", filePath: "test.swift")
    #expect(feedback == nil)
  }

  @Test("console output captured")
  func consoleCapture() {
    let result = validator.validate(code: """
      console.log("line 1");
      console.log("line 2");
      console.warn("warning");
    """)
    #expect(result.valid)
    #expect(result.output?.contains("line 1") == true)
    #expect(result.output?.contains("warning") == true)
  }
}
