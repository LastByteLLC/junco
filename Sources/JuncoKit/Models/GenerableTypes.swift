// GenerableTypes.swift — Structured output types for each pipeline stage
//
// Each type is @Generable (for AFM structured output) and Codable.
// Per TN3193: keep types small, use short property names, @Guide only where needed.
// The schema is serialized as JSON and passed in-prompt — every description costs tokens.

import FoundationModels

// MARK: - Stage 1: Intent Classification

@Generable
public struct AgentIntent: Codable, Sendable {
  @Guide(description: "swift, javascript, or general")
  public var domain: String

  @Guide(description: "fix, add, refactor, explain, test, or explore")
  public var taskType: String

  @Guide(description: "simple, moderate, or complex")
  public var complexity: String

  public var targets: [String]
}

// MARK: - Stage 2: Strategy Selection

@Generable
public struct AgentStrategy: Codable, Sendable {
  @Guide(description: "decompose, debug-trace, test-first, read-then-edit, or search-then-plan")
  public var approach: String

  public var startingPoints: [String]
  public var risk: String
}

// MARK: - Stage 3: Planning

@Generable
public struct AgentPlan: Codable, Sendable {
  public var steps: [PlanStep]
}

@Generable
public struct PlanStep: Codable, Sendable {
  public var instruction: String

  @Guide(description: "bash, read, create, write, edit, patch, or search")
  public var tool: String

  public var target: String
}

// MARK: - Stage 4: Execution (Tool Choice)

@Generable
public struct ToolChoice: Codable, Sendable {
  @Guide(description: "bash, read, create, write, edit, patch, or search")
  public var tool: String

  public var reasoning: String
}

// MARK: - Stage 4: Execution (Tool Parameters)

@Generable
public struct BashParams: Codable, Sendable {
  public var command: String
}

@Generable
public struct ReadParams: Codable, Sendable {
  public var filePath: String
}

/// Still used as fallback when plan target is empty.
@Generable
public struct CreateParams: Codable, Sendable {
  public var filePath: String
  public var content: String
}

@Generable
public struct WriteParams: Codable, Sendable {
  public var filePath: String
  public var content: String
}

@Generable
public struct EditParams: Codable, Sendable {
  public var filePath: String

  @Guide(description: "Exact text to find — use a full line, not a single word")
  public var find: String

  public var replace: String
}

@Generable
public struct SearchParams: Codable, Sendable {
  public var pattern: String
}

@Generable
public struct PatchParams: Codable, Sendable {
  public var filePath: String
  public var patch: String
}

/// Unified action result for internal use (not @Generable).
public enum ToolAction: Sendable {
  case bash(command: String)
  case read(path: String)
  case create(path: String, content: String)
  case write(path: String, content: String)
  case edit(path: String, find: String, replace: String)
  case patch(path: String, diff: String)
  case search(pattern: String)
}

// MARK: - Stage 5: Reflection

@Generable
public struct AgentReflection: Codable, Sendable {
  public var taskSummary: String
  public var insight: String
  public var improvement: String
  public var succeeded: Bool
}

// MARK: - Step Completion Check

@Generable
public struct StepCheck: Codable, Sendable {
  public var complete: Bool
  public var remaining: String
}

// MARK: - Two-Phase Code Generation

@Generable
public struct CodeSkeleton: Codable, Sendable {
  public var imports: String
  public var typeDeclaration: String
  public var properties: String
  public var methodSignatures: [String]
}

@Generable
public struct MethodBody: Codable, Sendable {
  public var implementation: String
}
