// TokenBudgetTests.swift — Verify token estimation and truncation

import Testing
@testable import JuncoKit

@Suite("TokenBudget")
struct TokenBudgetTests {

  @Test("estimates roughly 1 token per 4 characters")
  func estimation() {
    // 100 characters → ~25 tokens
    let text = String(repeating: "a", count: 100)
    let estimate = TokenBudget.estimate(text)
    #expect(estimate == 25)
  }

  @Test("empty string returns 1 token minimum")
  func emptyEstimate() {
    #expect(TokenBudget.estimate("") == 1)
  }

  @Test("truncation preserves text under budget")
  func noTruncation() {
    let text = "short text"
    let result = TokenBudget.truncate(text, toTokens: 100)
    #expect(result == text)
  }

  @Test("truncation cuts text over budget")
  func truncates() {
    let text = String(repeating: "x", count: 1000)  // ~250 tokens
    let result = TokenBudget.truncate(text, toTokens: 50)
    #expect(TokenBudget.estimate(result) < 100)  // Rough check, includes marker
    #expect(result.contains("truncated"))
  }

  @Test("all stage budgets fit within context window")
  func budgetsFit() {
    let stages: [StageBudget] = [
      TokenBudget.classify,
      TokenBudget.strategy,
      TokenBudget.plan,
      TokenBudget.execute,
      TokenBudget.observe,
      TokenBudget.reflect,
    ]

    for stage in stages {
      #expect(stage.total <= TokenBudget.contextWindow,
        "Stage budget \(stage.total) exceeds context window \(TokenBudget.contextWindow)")
    }
  }

  @Test("estimate handles multi-string arrays")
  func multiEstimate() {
    let texts = ["hello", "world", "test"]
    let total = TokenBudget.estimate(texts)
    #expect(total > 0)
    #expect(total == texts.map { TokenBudget.estimate($0) }.reduce(0, +))
  }
}
