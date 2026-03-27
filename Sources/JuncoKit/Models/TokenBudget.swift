// TokenBudget.swift — Token estimation and budget management
//
// AFM has a ~4096 token context window. Every token matters.
// Approximation: 1 token ~ 4 characters (conservative for code).

/// Token budget constants for each pipeline stage.
public enum TokenBudget {
  /// Total AFM context window.
  public static let contextWindow = 4096

  // MARK: - Per-stage budgets

  /// Intent classification stage.
  public static let classify = StageBudget(
    system: 100, context: 200, prompt: 100, generation: 400
  )

  /// Strategy selection stage.
  public static let strategy = StageBudget(
    system: 100, context: 200, prompt: 100, generation: 400
  )

  /// Planning stage — needs more context for file listings.
  public static let plan = StageBudget(
    system: 150, context: 500, prompt: 150, generation: 800
  )

  /// Execution stage — needs code context.
  public static let execute = StageBudget(
    system: 150, context: 800, prompt: 200, generation: 1500
  )

  /// Observation compression.
  public static let observe = StageBudget(
    system: 80, context: 600, prompt: 80, generation: 300
  )

  /// Post-task reflection.
  public static let reflect = StageBudget(
    system: 100, context: 300, prompt: 100, generation: 400
  )

  // MARK: - Estimation

  /// Estimate token count from a string.
  /// Conservative: 1 token per 4 characters for English/code mix.
  public static func estimate(_ text: String) -> Int {
    max(1, text.utf8.count / 4)
  }

  /// Estimate token count from multiple strings.
  public static func estimate(_ texts: [String]) -> Int {
    texts.reduce(0) { $0 + estimate($1) }
  }

  /// Truncate text to fit within a token budget.
  /// Prefers truncating from the middle (keeps start and end of code).
  public static func truncate(_ text: String, toTokens limit: Int) -> String {
    let currentTokens = estimate(text)
    guard currentTokens > limit else { return text }

    let charLimit = limit * 4
    guard charLimit > 40 else { return String(text.prefix(charLimit)) }

    // Keep first 60% and last 30%, with a marker in the middle
    let keepStart = Int(Double(charLimit) * 0.6)
    let keepEnd = Int(Double(charLimit) * 0.3)
    let marker = "\n... [truncated \(currentTokens - limit) tokens] ...\n"

    let startIdx = text.index(text.startIndex, offsetBy: min(keepStart, text.count))
    let endIdx = text.index(text.endIndex, offsetBy: -min(keepEnd, text.count))

    return String(text[..<startIdx]) + marker + String(text[endIdx...])
  }
}

/// Budget allocation for a single pipeline stage.
public struct StageBudget: Sendable {
  /// Tokens reserved for system prompt.
  public let system: Int
  /// Tokens reserved for context (code, memory, reflections).
  public let context: Int
  /// Tokens reserved for the user prompt (step instruction, query).
  public let prompt: Int
  /// Tokens available for generation.
  public let generation: Int

  /// Total tokens this stage will use.
  public var total: Int { system + context + prompt + generation }

  /// Tokens available for injected content (context budget).
  public var availableContext: Int { context }

  public init(system: Int, context: Int, prompt: Int, generation: Int) {
    self.system = system
    self.context = context
    self.prompt = prompt
    self.generation = generation
  }
}
