// StructuredFixBuilderTests.swift — Tests for compiler error pattern matching

import Foundation
import Testing
@testable import JuncoKit

@Suite("StructuredFixBuilder")
struct StructuredFixBuilderTests {

  let builder = StructuredFixBuilder()

  // MARK: - Redundant Conformance

  @Test("Detects redundant conformance and builds exact fix")
  func redundantConformance() {
    let error = BuildError(
      filePath: "Model.swift", line: 3, column: 1,
      message: "redundant conformance of 'Podcast' to protocol 'Identifiable'"
    )
    let region = CodeRegion(
      text: "import Foundation\n\nstruct Podcast: Codable, Identifiable {\n    var id = UUID()\n}",
      startLine: 0, endLine: 4
    )
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .exact)
    #expect(fix?.replacement?.contains("Identifiable") == false)
    #expect(fix?.replacement?.contains("Codable") == true)
  }

  // MARK: - Incorrect Argument Label

  @Test("Detects incorrect argument label and builds exact fix")
  func incorrectLabel() {
    let error = BuildError(
      filePath: "Service.swift", line: 7, column: 20,
      message: "incorrect argument label in call (have 'term:', expected 'query:')"
    )
    let region = CodeRegion(
      text: "func search() {\n    let results = api.search(term: text)\n}",
      startLine: 5, endLine: 7
    )
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .exact)
    #expect(fix?.replacement?.contains("query:") == true)
    #expect(fix?.replacement?.contains("term:") == false)
  }

  // MARK: - Extra Argument

  @Test("Detects extra argument and builds fix")
  func extraArgument() {
    let error = BuildError(
      filePath: "View.swift", line: 10, column: 30,
      message: "extra argument 'style' in call"
    )
    let region = CodeRegion(
      text: "Image(systemName: \"star\", style: .large)",
      startLine: 9, endLine: 9
    )
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix != nil)
    // Should either be exact (if regex removed it) or likely
    #expect(fix?.description.contains("style") == true)
  }

  // MARK: - No Member

  @Test("Detects no member error with snapshot info")
  func noMemberWithSnapshot() {
    let error = BuildError(
      filePath: "View.swift", line: 8, column: 15,
      message: "value of type 'Podcast' has no member 'Podcast'"
    )
    let region = CodeRegion(
      text: "Text(item.Podcast)",
      startLine: 7, endLine: 7
    )
    let snapshot = ProjectSnapshot(
      models: [TypeSummary(name: "Podcast", file: "Podcast.swift", kind: "struct", properties: ["name", "author"], methods: [], conformances: ["Codable"])],
      views: [], services: [],
      navigationPattern: nil, testPattern: nil, keyFiles: [:]
    )
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: snapshot
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .likely)
    #expect(fix?.description.contains("name") == true)
    #expect(fix?.description.contains("author") == true)
  }

  @Test("No member error without snapshot falls back to hint")
  func noMemberWithoutSnapshot() {
    let error = BuildError(
      filePath: "View.swift", line: 8, column: 15,
      message: "value of type 'SomeType' has no member 'foo'"
    )
    let region = CodeRegion(text: "x.foo()", startLine: 7, endLine: 7)
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .hint)
  }

  // MARK: - Type Mismatch

  @Test("Detects type mismatch with API hint")
  func typeMismatch() {
    let error = BuildError(
      filePath: "Model.swift", line: 5, column: 20,
      message: "cannot convert value of type 'Int' to expected argument type 'String'"
    )
    let region = CodeRegion(text: "let x = foo(42)", startLine: 4, endLine: 4)
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region,
      apiHint: "func foo(_ value: String) -> Bool",
      snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .likely)
    #expect(fix?.description.contains("Int") == true)
    #expect(fix?.description.contains("String") == true)
  }

  // MARK: - Missing Argument

  @Test("Detects missing argument with API hint")
  func missingArgument() {
    let error = BuildError(
      filePath: "Service.swift", line: 12, column: 10,
      message: "missing argument for parameter 'decoder' in call"
    )
    let region = CodeRegion(text: "let data = try parse(json)", startLine: 11, endLine: 11)
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region,
      apiHint: "func parse(_ data: Data, decoder: JSONDecoder) -> Any",
      snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .likely)
    #expect(fix?.description.contains("decoder") == true)
  }

  // MARK: - Unresolved Identifier

  @Test("Detects unresolved identifier")
  func unresolvedIdentifier() {
    let error = BuildError(
      filePath: "ViewModel.swift", line: 15, column: 5,
      message: "use of unresolved identifier 'searchText'"
    )
    let region = CodeRegion(text: "filter(searchText)", startLine: 14, endLine: 14)
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix != nil)
    #expect(fix?.confidence == .hint)
    #expect(fix?.description.contains("searchText") == true)
  }

  // MARK: - No Match

  @Test("Returns nil for unrecognized error")
  func noMatch() {
    let error = BuildError(
      filePath: "File.swift", line: 1, column: 1,
      message: "some unusual compiler error"
    )
    let region = CodeRegion(text: "let x = 1", startLine: 0, endLine: 0)
    let fix = builder.buildFixInstruction(
      error: error, codeRegion: region, apiHint: nil, snapshot: .empty
    )
    #expect(fix == nil)
  }
}
