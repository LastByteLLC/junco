// ProgressiveCompressorTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("ProgressiveCompressor")
struct ProgressiveCompressorTests {
  let compressor = ProgressiveCompressor()

  let sampleCode = """
    import Foundation

    /// A sample service for testing.
    public struct SampleService: Sendable {
      public let name: String
      private var count: Int = 0

      /// Initialize with a name.
      public init(name: String) {
        self.name = name
        self.count = 0
      }

      /// Process an item and return the result.
      public func process(item: String) -> String {
        let result = item.uppercased()
        count += 1
        print("Processed \\(count) items")
        return result
      }

      /// Reset the counter.
      public func reset() {
        count = 0
      }
    }
    """

  // MARK: - Tier Selection

  @Test("full tier preserves all content when under budget")
  func fullTier() {
    let result = compressor.compress(code: sampleCode, target: 500)
    #expect(result.tier == .full)
    #expect(result.compressed == sampleCode)
    #expect(result.tokensSaved == 0)
  }

  @Test("gist tier keeps signatures, drops bodies")
  func gistTier() {
    let result = compressor.compress(code: sampleCode, target: 100)
    #expect(result.tier == .gist)
    #expect(result.compressed.contains("import Foundation"))
    #expect(result.compressed.contains("public struct SampleService"))
    #expect(result.compressed.contains("public let name: String"))
    #expect(result.compressed.contains("func process"))
    #expect(result.compressed.contains("func reset"))
    // Bodies should be dropped
    #expect(!result.compressed.contains("uppercased"))
    #expect(!result.compressed.contains("Processed"))
  }

  @Test("micro tier keeps only symbol names")
  func microTier() {
    let result = compressor.compress(code: sampleCode, target: 25)
    #expect(result.tier == .micro)
    if result.tier == .micro {
      #expect(result.compressed.contains("SampleService"))
      #expect(result.compressed.contains("process"))
      #expect(result.compressed.contains("reset"))
      #expect(!result.compressed.contains("{"))
    }
  }

  @Test("dropped tier when nothing fits")
  func droppedTier() {
    let result = compressor.compress(code: sampleCode, target: 1)
    #expect(result.tier == .dropped)
    #expect(result.compressed.isEmpty)
  }

  // MARK: - Code Gist

  @Test("gist preserves import statements")
  func gistImports() {
    let gist = compressor.codeGist(sampleCode)
    #expect(gist.contains("import Foundation"))
  }

  @Test("gist preserves doc comments on declarations")
  func gistDocComments() {
    let gist = compressor.codeGist(sampleCode)
    #expect(gist.contains("/// A sample service"))
    #expect(gist.contains("/// Process an item"))
  }

  @Test("gist preserves property declarations")
  func gistProperties() {
    let gist = compressor.codeGist(sampleCode)
    #expect(gist.contains("public let name: String"))
    #expect(gist.contains("private var count"))
  }

  @Test("gist drops function body implementation")
  func gistDropsBodies() {
    let gist = compressor.codeGist(sampleCode)
    #expect(!gist.contains("uppercased"))
    #expect(!gist.contains("print("))
  }

  @Test("gist is significantly smaller than original")
  func gistSize() {
    let gist = compressor.codeGist(sampleCode)
    let originalTokens = TokenBudget.estimate(sampleCode)
    let gistTokens = TokenBudget.estimate(gist)
    // Gist should be significantly smaller than original
    #expect(gistTokens < originalTokens * 75 / 100, "Gist too large: \(gistTokens) vs \(originalTokens)")
  }

  // MARK: - Code Micro

  @Test("micro extracts symbol names")
  func microSymbols() {
    let micro = compressor.codeMicro(sampleCode)
    #expect(micro.contains("SampleService"))
    #expect(micro.contains("process"))
    #expect(micro.contains("reset"))
    #expect(micro.contains("name"))
  }

  @Test("micro is very compact")
  func microSize() {
    let micro = compressor.codeMicro(sampleCode)
    let microTokens = TokenBudget.estimate(micro)
    let originalTokens = TokenBudget.estimate(sampleCode)
    #expect(microTokens < originalTokens / 4, "Micro too large: \(microTokens) vs \(originalTokens)")
  }

  // MARK: - Multi-Section Compression

  @Test("compressSections respects priority order")
  func sectionPriority() {
    let sections = [
      (content: sampleCode, priority: 90),
      (content: "Low priority filler text that takes up space", priority: 10)
    ]
    let results = compressor.compressSections(sections, totalBudget: 120)
    // High priority section should get lighter compression than low priority
    #expect(results.count >= 1)
    #expect(results[0].tier == .full || results[0].tier == .gist)
  }

  @Test("compressSections stays within total budget")
  func sectionBudget() {
    let sections = [
      (content: sampleCode, priority: 90),
      (content: sampleCode, priority: 50),
      (content: sampleCode, priority: 10)
    ]
    let results = compressor.compressSections(sections, totalBudget: 80)
    let totalTokens = results.reduce(0) { $0 + $1.compressedTokens }
    #expect(totalTokens <= 80, "Exceeded budget: \(totalTokens) > 80")
  }

  // MARK: - Determinism

  @Test("compression of same input produces same output")
  func deterministic() {
    let r1 = compressor.compress(code: sampleCode, target: 30)
    let r2 = compressor.compress(code: sampleCode, target: 30)
    #expect(r1.compressed == r2.compressed)
    #expect(r1.tier == r2.tier)
    #expect(r1.compressedTokens == r2.compressedTokens)
  }
}
