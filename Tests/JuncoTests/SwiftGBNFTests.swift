// SwiftGBNFTests.swift — Tests for GBNF grammar definitions

import Foundation
import Testing
@testable import JuncoKit

@Suite("SwiftGBNF")
struct SwiftGBNFTests {

  // MARK: - Grammar Selection

  @Test("grammar(for:) returns grammar for view role")
  func grammarForView() {
    let grammar = SwiftGBNF.grammar(for: "view")
    #expect(grammar != nil)
    #expect(grammar!.contains("view-struct"))
  }

  @Test("grammar(for:) returns grammar for viewmodel role")
  func grammarForViewModel() {
    let grammar = SwiftGBNF.grammar(for: "viewmodel")
    #expect(grammar != nil)
  }

  @Test("grammar(for:) returns grammar for service role")
  func grammarForService() {
    let grammar = SwiftGBNF.grammar(for: "service")
    #expect(grammar != nil)
  }

  @Test("grammar(for:) returns grammar for model role")
  func grammarForModel() {
    let grammar = SwiftGBNF.grammar(for: "model")
    #expect(grammar != nil)
  }

  // MARK: - Grammar Validity

  @Test("swiftFile grammar has root rule")
  func swiftFileHasRoot() {
    #expect(SwiftGBNF.swiftFile.contains("root ::="))
  }

  @Test("swiftUIViewBody grammar has root rule")
  func swiftUIViewHasRoot() {
    #expect(SwiftGBNF.swiftUIViewBody.contains("root ::="))
  }

  @Test("structBody grammar has root rule")
  func structBodyHasRoot() {
    #expect(SwiftGBNF.structBody.contains("root ::="))
  }

  @Test("swiftFile grammar passes basic validation")
  func swiftFileValid() {
    #expect(SwiftGBNF.isValidGBNF(SwiftGBNF.swiftFile))
  }

  @Test("swiftUIViewBody grammar passes basic validation")
  func swiftUIViewValid() {
    #expect(SwiftGBNF.isValidGBNF(SwiftGBNF.swiftUIViewBody))
  }

  @Test("structBody grammar passes basic validation")
  func structBodyValid() {
    #expect(SwiftGBNF.isValidGBNF(SwiftGBNF.structBody))
  }

  @Test("invalid grammar fails validation")
  func invalidGrammar() {
    #expect(!SwiftGBNF.isValidGBNF("not a grammar"))
    #expect(!SwiftGBNF.isValidGBNF(""))
  }

  // MARK: - Grammar Content

  @Test("swiftFile grammar enforces imports first")
  func swiftFileImportsFirst() {
    let grammar = SwiftGBNF.swiftFile
    #expect(grammar.contains("imports"))
    #expect(grammar.contains("import-stmt"))
  }

  @Test("swiftUIViewBody grammar enforces View conformance")
  func swiftUIViewConformance() {
    let grammar = SwiftGBNF.swiftUIViewBody
    #expect(grammar.contains("view-conformances"))
    #expect(grammar.contains("body-decl"))
  }

  @Test("structBody grammar supports async throws")
  func structBodyAsyncThrows() {
    let grammar = SwiftGBNF.structBody
    #expect(grammar.contains("async-throws"))
  }

  // MARK: - LLMGenerationOptions grammar field

  @Test("LLMGenerationOptions carries grammar")
  func optionsGrammar() {
    let opts = LLMGenerationOptions(grammar: "root ::= \"hello\"")
    #expect(opts.grammar == "root ::= \"hello\"")
  }

  @Test("LLMGenerationOptions defaults grammar to nil")
  func optionsGrammarDefault() {
    let opts = LLMGenerationOptions(temperature: 0.5)
    #expect(opts.grammar == nil)
  }
}
