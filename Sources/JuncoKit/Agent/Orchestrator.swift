// Orchestrator.swift — Main agent pipeline
//
// classify → strategy → plan → execute (2-phase) → reflect
// Each stage is a separate LLM call. Working memory bridges stages.
//
// Debug mode: set verbose=true to log every stage's input/output.
// Conversational queries (greetings, meta-questions) are handled
// directly without entering the coding pipeline.

import Foundation

public actor Orchestrator {

  private let adapter: AFMAdapter
  private let shell: SafeShell
  private let files: FileTools
  private let contextPacker: ContextPacker
  private let reflectionStore: ReflectionStore
  private let workingDirectory: String
  public let domain: DomainConfig
  private let intentClassifier: IntentClassifier

  private var projectIndex: [IndexEntry] = []

  /// Enable verbose debug output to stderr.
  public private(set) var verbose: Bool = false

  public func setVerbose(_ value: Bool) { verbose = value }

  public private(set) var metrics: SessionMetrics

  public init(adapter: AFMAdapter, workingDirectory: String) {
    self.adapter = adapter
    self.workingDirectory = workingDirectory
    self.shell = SafeShell(workingDirectory: workingDirectory)
    self.files = FileTools(workingDirectory: workingDirectory)
    self.contextPacker = ContextPacker(workingDirectory: workingDirectory)
    self.reflectionStore = ReflectionStore(projectDirectory: workingDirectory)
    self.domain = DomainDetector(workingDirectory: workingDirectory).detect()
    self.intentClassifier = IntentClassifier()
    self.metrics = SessionMetrics()
  }

  // MARK: - Public API

  public func run(query: String) async throws -> RunResult {
    var memory = WorkingMemory(query: query)

    // Check for conversational/meta queries first
    if let directResponse = handleConversational(query) {
      let reflection = AgentReflection(
        taskSummary: "Conversational query",
        insight: directResponse,
        improvement: "",
        succeeded: true
      )
      return RunResult(memory: memory, reflection: reflection)
    }

    // Build project index using domain-specific extensions
    let indexer = FileIndexer(workingDirectory: workingDirectory)
    projectIndex = indexer.indexProject(extensions: domain.fileExtensions)
    debug("Indexed \(projectIndex.count) symbols from \(domain.displayName) project")

    let intent = try await classify(query: query, memory: &memory)
    memory.intent = intent
    debug("CLASSIFY → domain:\(intent.domain) type:\(intent.taskType) complexity:\(intent.complexity) targets:\(intent.targets)")

    let strategy = try await discoverStrategy(query: query, intent: intent, memory: &memory)
    memory.strategy = strategy
    debug("STRATEGY → approach:\(strategy.approach) start:\(strategy.startingPoints) risk:\(strategy.risk)")

    let plan = try await plan(query: query, intent: intent, strategy: strategy, memory: &memory)
    memory.plan = plan
    debug("PLAN → \(plan.steps.count) steps:")
    for (i, step) in plan.steps.enumerated() {
      debug("  [\(i + 1)] \(step.tool): \(step.instruction) → \(step.target)")
    }

    for (index, step) in plan.steps.enumerated() {
      memory.currentStepIndex = index
      do {
        let observation = try await executeStep(step: step, memory: &memory)
        memory.addObservation(observation)
        debug("EXEC[\(index + 1)] → [\(observation.outcome)] \(observation.tool): \(observation.keyFact)")
      } catch {
        memory.addError("Step \(index + 1): \(error)")
        memory.addObservation(StepObservation(
          tool: step.tool, outcome: "error", keyFact: "\(error)"
        ))
        debug("EXEC[\(index + 1)] → [ERROR] \(error)")
      }
    }

    let reflection = try await reflect(memory: &memory)
    debug("REFLECT → succeeded:\(reflection.succeeded) insight:\(reflection.insight)")

    try? reflectionStore.save(query: query, reflection: reflection)

    metrics.tasksCompleted += 1
    metrics.totalTokensUsed += memory.totalTokensUsed
    metrics.totalLLMCalls += memory.llmCalls

    return RunResult(memory: memory, reflection: reflection)
  }

  // MARK: - Conversational Query Handling

  /// Detect and respond to non-coding queries directly.
  /// Returns a response string if handled, nil if it should go through the pipeline.
  private func handleConversational(_ query: String) -> String? {
    let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    // Identity / meta questions
    let identityPatterns = [
      "who are you", "what are you", "introduce yourself",
      "what is junco", "what can you do", "help me",
    ]
    if identityPatterns.contains(where: { lower.contains($0) }) {
      return "I'm junco, an on-device AI coding agent running on Apple Foundation Models. " +
        "I can fix bugs, add features, refactor code, explain code, write tests, and search your project. " +
        "I work entirely locally — no cloud, no API keys. " +
        "Detected domain: \(domain.displayName). Type /help for commands."
    }

    // Greetings
    let greetings = ["hello", "hi", "hey", "good morning", "good evening", "howdy", "sup"]
    if greetings.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
      return "Hello! I'm junco, your local coding agent. What would you like to work on? " +
        "Try something like: fix the bug in @main.swift, or: explain the auth module."
    }

    // Thank you
    if lower.contains("thank") || lower == "thanks" || lower == "ty" {
      return "You're welcome! Let me know if there's anything else."
    }

    // Too short / ambiguous to be a coding task (single word that isn't a known command)
    let words = lower.split(separator: " ")
    if words.count == 1 {
      let knownSingleWords = Set(["fix", "test", "tests", "refactor", "search", "grep", "find", "build", "run", "lint", "explain"])
      if !knownSingleWords.contains(lower) {
        return nil  // Let the pipeline handle it — might be a file name
      }
    }

    return nil
  }

  // MARK: - Pipeline Stages

  private func classify(query: String, memory: inout WorkingMemory) async throws -> AgentIntent {
    // Try ML classifier first (10ms vs 2s LLM call)
    if let mlResult = intentClassifier.classifyWithConfidence(query), mlResult.confidence > Config.mlClassifierConfidence {
      metrics.mlClassifications += 1
      debug("ML classifier: \(mlResult.label) (confidence: \(String(format: "%.2f", mlResult.confidence)))")

      let fileList = files.listFiles()
      let targets = fileList.filter { path in
        query.lowercased().contains((path as NSString).lastPathComponent.lowercased())
      }
      return AgentIntent(
        domain: domain.kind.rawValue,
        taskType: mlResult.label,
        complexity: targets.count > 2 ? "moderate" : "simple",
        targets: targets.isEmpty ? Array(fileList.prefix(3)) : targets
      )
    }

    // Fall back to LLM
    debug("ML classifier: low confidence, falling back to LLM")
    let fileList = files.listFiles().prefix(25).joined(separator: "\n")
    let prompt = Prompts.classifyPrompt(
      query: query,
      fileHints: TokenBudget.truncate(fileList, toTokens: 150)
    )
    memory.trackCall(estimatedTokens: TokenBudget.classify.total)
    return try await adapter.generateStructured(
      prompt: prompt, system: Prompts.classifySystem, as: AgentIntent.self
    )
  }

  private func discoverStrategy(
    query: String, intent: AgentIntent, memory: inout WorkingMemory
  ) async throws -> AgentStrategy {
    let prompt = Prompts.strategyPrompt(query: query, intent: intent)
    memory.trackCall(estimatedTokens: TokenBudget.strategy.total)
    return try await adapter.generateStructured(
      prompt: prompt, system: Prompts.strategySystem, as: AgentStrategy.self
    )
  }

  private func plan(
    query: String, intent: AgentIntent, strategy: AgentStrategy,
    memory: inout WorkingMemory
  ) async throws -> AgentPlan {
    let fileContext = contextPacker.pack(
      query: query,
      index: projectIndex,
      budget: TokenBudget.plan.context,
      preferredFiles: strategy.startingPoints
    )

    let prompt = Prompts.planPrompt(
      query: query, intent: intent, strategy: strategy,
      fileContext: fileContext
    )
    memory.trackCall(estimatedTokens: TokenBudget.plan.total)
    return try await adapter.generateStructured(
      prompt: prompt, system: Prompts.planSystem, as: AgentPlan.self
    )
  }

  private func executeStep(
    step: PlanStep, memory: inout WorkingMemory
  ) async throws -> StepObservation {
    let codeContext: String
    if !step.target.isEmpty, files.exists(step.target) {
      codeContext = (try? files.read(path: step.target, maxTokens: 600)) ?? ""
    } else {
      codeContext = contextPacker.pack(
        query: step.instruction,
        index: projectIndex,
        budget: 600,
        preferredFiles: Array(memory.touchedFiles)
      )
    }
    let memoryStr = memory.compactDescription(tokenBudget: 200)
    let reflectionHint = reflectionStore.formatForPrompt(query: memory.query)

    let prompt = Prompts.executePrompt(
      step: step, memory: memoryStr, codeContext: codeContext, reflection: reflectionHint
    )

    // Phase 1: Choose tool
    memory.trackCall(estimatedTokens: 600)
    let choice = try await adapter.generateStructured(
      prompt: prompt,
      system: Prompts.executeSystem(domainHint: domain.promptHint),
      as: ToolChoice.self
    )
    debug("  tool choice: \(choice.tool) — \(choice.reasoning)")

    // Phase 2: Resolve and execute
    let action = try await resolveToolAction(
      tool: choice.tool, step: step, codeContext: codeContext, memory: &memory
    )
    debug("  action: \(action)")

    let toolOutput = await executeToolSafe(action: action, memory: &memory)

    return compressObservation(tool: choice.tool, output: toolOutput, step: step.instruction)
  }

  private func resolveToolAction(
    tool: String, step: PlanStep, codeContext: String,
    memory: inout WorkingMemory
  ) async throws -> ToolAction {
    let base = "Step: \(step.instruction)\nTarget: \(step.target)"
    memory.trackCall(estimatedTokens: 600)

    switch tool.lowercased() {
    case "bash":
      let p = try await adapter.generateStructured(
        prompt: base,
        system: "Generate a bash command. Working directory is the project root.",
        as: BashParams.self
      )
      return .bash(command: p.command)

    case "read":
      if !step.target.isEmpty, files.exists(step.target) {
        return .read(path: step.target)
      }
      let p = try await adapter.generateStructured(
        prompt: base, system: "Specify the file path to read.", as: ReadParams.self
      )
      return .read(path: p.filePath)

    case "write":
      let p = try await adapter.generateStructured(
        prompt: "\(base)\n\nExisting:\n\(codeContext)",
        system: "Generate file path and complete content to write.",
        as: WriteParams.self
      )
      return .write(path: p.filePath, content: p.content)

    case "edit":
      let p = try await adapter.generateStructured(
        prompt: "\(base)\n\nFile content:\n\(codeContext)",
        system: "Specify exact text to find and its replacement. Find text must match the file exactly.",
        as: EditParams.self
      )
      return .edit(path: p.filePath, find: p.find, replace: p.replace)

    case "search":
      let p = try await adapter.generateStructured(
        prompt: base, system: "Specify a grep pattern.", as: SearchParams.self
      )
      return .search(pattern: p.pattern)

    default:
      return .bash(command: "echo 'Unknown tool: \(tool)'")
    }
  }

  private func reflect(memory: inout WorkingMemory) async throws -> AgentReflection {
    let prompt = Prompts.reflectPrompt(memory: memory)
    memory.trackCall(estimatedTokens: TokenBudget.reflect.total)
    return try await adapter.generateStructured(
      prompt: prompt, system: Prompts.reflectSystem, as: AgentReflection.self
    )
  }

  // MARK: - Tool Execution

  private func executeToolSafe(action: ToolAction, memory: inout WorkingMemory) async -> String {
    do {
      return try await executeTool(action: action, memory: &memory)
    } catch {
      return "ERROR: \(error)"
    }
  }

  private func executeTool(action: ToolAction, memory: inout WorkingMemory) async throws -> String {
    switch action {
    case .bash(let command):
      metrics.bashCommandsRun += 1
      let result = try await shell.execute(command)
      return result.formatted(maxTokens: Config.toolOutputMaxTokens)

    case .read(let path):
      memory.touch(path)
      return try files.read(path: path, maxTokens: Config.fileReadMaxTokens)

    case .write(let path, let content):
      memory.touch(path)
      metrics.filesModified += 1
      try files.write(path: path, content: content)
      return "Written \(path) (\(content.count) chars)"

    case .edit(let path, let find, let replace):
      memory.touch(path)
      metrics.filesModified += 1
      do {
        try files.edit(path: path, find: find, replace: replace)
        return "Edited \(path)"
      } catch is FileToolError {
        try files.edit(path: path, find: find, replace: replace, fuzzy: true)
        return "Edited \(path) (fuzzy match)"
      }

    case .search(let pattern):
      let cmd = "grep -rn \(shellEscape(pattern)) . --include='*.swift' --include='*.js' --include='*.ts' --include='*.css' --include='*.html' | head -20"
      let result = try await shell.execute(cmd)
      return result.formatted(maxTokens: Config.toolOutputMaxTokens)
    }
  }

  private func compressObservation(tool: String, output: String, step: String) -> StepObservation {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    let outcome = (output.contains("ERROR") || output.contains("failed")) ? "error" : "ok"
    let keyFact = lines.first.map(String.init) ?? "no output"
    return StepObservation(tool: tool, outcome: outcome, keyFact: String(keyFact.prefix(120)))
  }

  private func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  // MARK: - Debug

  private func debug(_ message: String) {
    guard verbose else { return }
    FileHandle.standardError.write("[debug] \(message)\n".data(using: .utf8) ?? Data())
  }
}

// MARK: - Types

public struct RunResult: Sendable {
  public let memory: WorkingMemory
  public let reflection: AgentReflection
}

public enum OrchestratorError: Error, Sendable {
  case editFailed(String)
  case toolFailed(String)
}

public struct SessionMetrics: Sendable {
  public var tasksCompleted: Int = 0
  public var totalTokensUsed: Int = 0
  public var totalLLMCalls: Int = 0
  public var filesModified: Int = 0
  public var bashCommandsRun: Int = 0
  public var mlClassifications: Int = 0
}
