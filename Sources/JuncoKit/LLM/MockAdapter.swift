// MockAdapter.swift — Deterministic adapter for testing

import os

/// A mock LLM adapter that returns preconfigured responses.
/// Tracks call history for assertion in tests.
public actor MockAdapter: LLMAdapter {
  public typealias Responder = @Sendable (String, String?) -> String

  private let responder: Responder
  private var _history: [(prompt: String, system: String?)] = []

  public var history: [(prompt: String, system: String?)] {
    _history
  }

  public var callCount: Int { _history.count }

  public init(responder: @escaping Responder = { _, _ in "mock response" }) {
    self.responder = responder
  }

  /// Convenience: returns the same string for every call.
  public init(fixedResponse: String) {
    self.responder = { _, _ in fixedResponse }
  }

  /// Convenience: returns responses in order, cycling if exhausted.
  public init(responses: [String]) {
    let lock = OSAllocatedUnfairLock(initialState: 0)
    self.responder = { _, _ in
      lock.withLock { idx -> String in
        let r = responses[idx % responses.count]
        idx += 1
        return r
      }
    }
  }

  public func generate(prompt: String, system: String?) async throws -> String {
    _history.append((prompt: prompt, system: system))
    return responder(prompt, system)
  }
}
