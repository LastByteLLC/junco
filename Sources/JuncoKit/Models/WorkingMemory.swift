// WorkingMemory.swift — Ephemeral state passed between pipeline stages
//
// Working memory is NOT stored in LLM context. It's a Swift struct
// that gets serialized into a compact string for prompt injection.
// Only the most relevant recent state is included.

import Foundation

/// Tracks agent state across the micro-conversation pipeline.
public struct WorkingMemory: Sendable {
  /// The original user query.
  public var query: String

  /// Classified intent (set after classify stage).
  public var intent: AgentIntent?

  /// Selected strategy (set after discover stage).
  public var strategy: AgentStrategy?

  /// Current plan (set after plan stage).
  public var plan: AgentPlan?

  /// Index of the current step being executed.
  public var currentStepIndex: Int = 0

  /// Observations from completed steps (auto-compacted to last N).
  public var observations: [StepObservation] = []

  /// Errors encountered during execution.
  public var errors: [String] = []

  /// Files that have been read or modified in this session.
  public var touchedFiles: Set<String> = []

  /// Number of LLM calls made so far.
  public var llmCalls: Int = 0

  /// Total tokens used (estimated).
  public var totalTokensUsed: Int = 0

  public init(query: String) {
    self.query = query
  }

  // MARK: - Compact serialization for prompt injection

  /// Serialize to a compact string that fits in the context budget.
  /// Target: ~200-300 tokens.
  public func compactDescription(tokenBudget: Int = 300) -> String {
    var parts: [String] = []

    parts.append("Task: \(query)")

    if let intent {
      parts.append("Domain: \(intent.domain) | Type: \(intent.taskType) | Complexity: \(intent.complexity)")
    }

    if let strategy {
      parts.append("Strategy: \(strategy.approach)")
    }

    if let plan {
      let total = plan.steps.count
      let done = currentStepIndex
      parts.append("Progress: step \(done + 1)/\(total)")
      if currentStepIndex < plan.steps.count {
        parts.append("Current: \(plan.steps[currentStepIndex].instruction)")
      }
    }

    // Last 2 observations only
    let recentObs = observations.suffix(2)
    for obs in recentObs {
      parts.append("[\(obs.tool)] \(obs.outcome): \(obs.keyFact)")
    }

    if !errors.isEmpty {
      parts.append("Errors: \(errors.suffix(2).joined(separator: "; "))")
    }

    if !touchedFiles.isEmpty {
      let fileList = touchedFiles.sorted().prefix(5).joined(separator: ", ")
      parts.append("Files: \(fileList)")
    }

    let result = parts.joined(separator: "\n")
    return TokenBudget.truncate(result, toTokens: tokenBudget)
  }

  // MARK: - Mutation helpers

  /// Record a completed step observation, auto-compacting to keep last 5.
  public mutating func addObservation(_ obs: StepObservation) {
    observations.append(obs)
    if observations.count > Config.maxObservations {
      observations = Array(observations.suffix(Config.maxObservations))
    }
  }

  /// Record an error.
  public mutating func addError(_ message: String) {
    errors.append(message)
    if errors.count > Config.maxErrors {
      errors = Array(errors.suffix(Config.maxErrors))
    }
  }

  /// Mark a file as touched.
  public mutating func touch(_ path: String) {
    touchedFiles.insert(path)
  }

  /// Advance to the next plan step.
  public mutating func advanceStep() {
    currentStepIndex += 1
  }

  /// Track an LLM call.
  public mutating func trackCall(estimatedTokens: Int) {
    llmCalls += 1
    totalTokensUsed += estimatedTokens
  }
}

/// A compact observation from a single tool execution.
public struct StepObservation: Sendable {
  /// Which tool was used.
  public let tool: String
  /// One-line outcome (success/failure/partial).
  public let outcome: String
  /// The single most important fact from the output.
  public let keyFact: String

  public init(tool: String, outcome: String, keyFact: String) {
    self.tool = tool
    self.outcome = outcome
    self.keyFact = keyFact
  }
}
