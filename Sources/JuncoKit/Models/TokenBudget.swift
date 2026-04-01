// TokenBudget.swift — Token estimation and budget management
//
// Per TN3193: "roughly three to four characters in Latin alphabet languages"
// Context window size derived from SystemLanguageModel.default.contextSize at runtime.

import FoundationModels

/// Token budget constants for each pipeline stage.
public enum TokenBudget {

  /// Context window size derived from the model at runtime.
  /// Falls back to 4096 only if the model is unavailable.
  public static var contextWindow: Int {
    SystemLanguageModel.default.contextSize
  }

  // MARK: - Per-stage budgets

  public static let classify = StageBudget(system: 100, context: 200, prompt: 100, generation: 400)
  public static let strategy = StageBudget(system: 100, context: 200, prompt: 100, generation: 400)
  public static let plan = StageBudget(system: 150, context: 500, prompt: 150, generation: 800)
  public static let execute = StageBudget(system: 150, context: 800, prompt: 200, generation: 1500)
  public static let observe = StageBudget(system: 80, context: 600, prompt: 80, generation: 300)
  public static let reflect = StageBudget(system: 100, context: 300, prompt: 100, generation: 400)

  // MARK: - Estimation

  /// Estimate token count from a string.
  /// TN3193: "roughly three to four characters" — use 4 for plain text, 3 for JSON.
  public static func estimate(_ text: String) -> Int {
    max(1, text.utf8.count / 4)
  }

  /// Estimate for structured output (JSON escaping inflates ~33%).
  public static func estimateStructured(_ text: String) -> Int {
    max(1, text.utf8.count / 3)
  }

  /// Estimate token count from multiple strings.
  public static func estimate(_ texts: [String]) -> Int {
    texts.reduce(0) { $0 + estimate($1) }
  }

  /// Truncate text to fit within a token budget.
  /// Keeps first 60% and last 30% with a marker in the middle.
  public static func truncate(_ text: String, toTokens limit: Int) -> String {
    let currentTokens = estimate(text)
    guard currentTokens > limit else { return text }

    let charLimit = limit * 4
    guard charLimit > 40 else { return String(text.prefix(charLimit)) }

    let keepStart = Int(Double(charLimit) * 0.6)
    let keepEnd = Int(Double(charLimit) * 0.3)
    let marker = "\n... [truncated] ...\n"

    let startIdx = text.index(text.startIndex, offsetBy: min(keepStart, text.count))
    let endIdx = text.index(text.endIndex, offsetBy: -min(keepEnd, text.count))

    return String(text[..<startIdx]) + marker + String(text[endIdx...])
  }
}

/// Budget allocation for a single pipeline stage.
public struct StageBudget: Sendable {
  public let system: Int
  public let context: Int
  public let prompt: Int
  public let generation: Int

  public var total: Int { system + context + prompt + generation }
  public var availableContext: Int { context }

  public init(system: Int, context: Int, prompt: Int, generation: Int) {
    self.system = system
    self.context = context
    self.prompt = prompt
    self.generation = generation
  }
}
