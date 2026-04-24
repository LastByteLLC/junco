// FixtureLoader.swift — Load hard-fixture JSON files into EvalCase structures.
//
// Fixtures live in `fixtures/hard/*.json` and describe:
//   - the query to run
//   - the target file expected
//   - declarative SubChecks to evaluate the generated file
//   - optional pre-populated files for edit/fix-type cases
//
// Kept deliberately minimal; the meta-harness can swap in different fixture
// directories for different experiments.

import Foundation
import JuncoKit

struct FixtureLoader {
  let workingDirectory: String

  /// Load every `*.json` under `fixtures/hard/` in lexicographic order.
  func loadAll() -> [EvalCase] {
    let dir = (workingDirectory as NSString).appendingPathComponent("fixtures/hard")
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
    return entries.sorted()
      .filter { $0.hasSuffix(".json") }
      .compactMap { name in
        let path = (dir as NSString).appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
          return try decode(data: data)
        } catch {
          FileHandle.standardError.write(Data("[FixtureLoader] Parse failed \(name): \(error)\n".utf8))
          return nil
        }
      }
  }

  private struct FixtureJSON: Decodable {
    let name: String
    let query: String
    let destructive: Bool?
    let expectedMode: String?
    let targetFile: String?
    let initialFiles: [String: String]?
    let qualityCriteria: [String]?
    let checks: [SubCheck]?
  }

  private func decode(data: Data) throws -> EvalCase {
    let f = try JSONDecoder().decode(FixtureJSON.self, from: data)
    let expected: AgentMode?
    switch f.expectedMode?.lowercased() {
    case "build": expected = .build
    case "answer": expected = .answer
    default: expected = nil
    }
    return EvalCase(
      name: f.name,
      query: f.query,
      referencedFiles: [],
      expectedMode: expected,
      destructive: f.destructive ?? true,
      setup: nil,
      qualityCriteria: f.qualityCriteria ?? [],
      targetFile: f.targetFile,
      initialFiles: f.initialFiles,
      checks: f.checks ?? []
    )
  }
}
