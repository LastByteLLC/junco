// MockAdapterTests.swift

import Testing
@testable import JuncoKit

@Suite("MockAdapter")
struct MockAdapterTests {

  @Test("fixed response returns same value every time")
  func fixedResponse() async throws {
    let adapter = MockAdapter(fixedResponse: "hello")
    let r1 = try await adapter.generate(prompt: "a", system: nil)
    let r2 = try await adapter.generate(prompt: "b", system: nil)
    #expect(r1 == "hello")
    #expect(r2 == "hello")
  }

  @Test("tracks call history")
  func history() async throws {
    let adapter = MockAdapter(fixedResponse: "ok")
    _ = try await adapter.generate(prompt: "p1", system: "s1")
    _ = try await adapter.generate(prompt: "p2", system: nil)

    let count = await adapter.callCount
    #expect(count == 2)

    let hist = await adapter.history
    #expect(hist[0].prompt == "p1")
    #expect(hist[0].system == "s1")
    #expect(hist[1].prompt == "p2")
    #expect(hist[1].system == nil)
  }

  @Test("response sequence cycles")
  func responseSequence() async throws {
    let adapter = MockAdapter(responses: ["a", "b", "c"])
    let r1 = try await adapter.generate(prompt: "1", system: nil)
    let r2 = try await adapter.generate(prompt: "2", system: nil)
    let r3 = try await adapter.generate(prompt: "3", system: nil)
    let r4 = try await adapter.generate(prompt: "4", system: nil)  // cycles
    #expect(r1 == "a")
    #expect(r2 == "b")
    #expect(r3 == "c")
    #expect(r4 == "a")
  }

  @Test("custom responder receives prompt and system")
  func customResponder() async throws {
    let adapter = MockAdapter { prompt, system in
      "\(system ?? "none"):\(prompt)"
    }
    let result = try await adapter.generate(prompt: "query", system: "sys")
    #expect(result == "sys:query")
  }
}
