// ContextBudgetTests.swift

import Testing
@testable import JuncoKit

@Suite("ContextBudget")
struct ContextBudgetTests {

  @Test("all buckets sum to less than context window for 4K")
  func budgetFits4K() {
    let budget = ContextBudget.forWindow(4096, stage: .execute)
    #expect(budget.total <= 4096, "Budget \(budget.total) exceeds 4096")
  }

  @Test("all stages produce valid budgets for 4K")
  func allStages4K() {
    for stage in [ContextBudget.Stage.classify, .plan, .execute, .reflect] {
      let budget = ContextBudget.forWindow(4096, stage: stage)
      #expect(budget.total <= 4096, "Stage budget \(budget.total) exceeds 4096")
      #expect(budget.generation > 0, "No generation budget")
      #expect(budget.safetyMargin > 0, "No safety margin")
    }
  }

  @Test("execute stage allocates most to fileContent and generation")
  func executeAllocation() {
    let budget = ContextBudget.forWindow(4096, stage: .execute)
    #expect(budget.fileContent >= budget.memory)
    #expect(budget.fileContent >= budget.retrieval)
    #expect(budget.generation >= budget.fileContent)
  }

  @Test("safety margin is at least 5% of window")
  func safetyMargin() {
    let budget = ContextBudget.forWindow(4096, stage: .execute)
    let minMargin = 4096 * Config.tokenSafetyMarginPercent / 100
    #expect(budget.safetyMargin >= minMargin)
  }

  @Test("forWindow scales with window size")
  func scaling() {
    let small = ContextBudget.forWindow(4096, stage: .execute)
    let large = ContextBudget.forWindow(8192, stage: .execute)
    // Larger window should have larger safety margin
    #expect(large.safetyMargin > small.safetyMargin)
  }

  @Test("no bucket has negative allocation")
  func noNegative() {
    let budget = ContextBudget.forWindow(4096, stage: .execute)
    #expect(budget.system >= 0)
    #expect(budget.fileContent >= 0)
    #expect(budget.memory >= 0)
    #expect(budget.retrieval >= 0)
    #expect(budget.reflections >= 0)
    #expect(budget.skillHints >= 0)
    #expect(budget.safetyMargin >= 0)
    #expect(budget.generation >= 0)
  }

  @Test("promptBudget excludes generation and safety")
  func promptBudget() {
    let budget = ContextBudget.forWindow(4096, stage: .execute)
    #expect(budget.promptBudget == budget.system + budget.fileContent + budget.memory +
            budget.retrieval + budget.reflections + budget.skillHints)
    #expect(budget.promptBudget < budget.total)
  }
}
