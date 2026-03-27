// Prompts.swift — Ultra-compact prompt templates for each pipeline stage
//
// Every prompt is designed to fit within its stage's token budget.
// No wasted tokens. No verbose instructions. The structured output
// types (@Generable) do the heavy lifting of constraining the response.

/// Prompt templates for each pipeline stage.
/// All templates use string interpolation for dynamic content.
public enum Prompts {

  // MARK: - Classify (~800 tokens total)

  public static let classifySystem = """
    You classify coding tasks. Respond with the structured fields only.
    """

  public static func classifyPrompt(query: String, fileHints: String) -> String {
    """
    Query: \(query)
    Project files: \(fileHints)
    """
  }

  // MARK: - Strategy (~800 tokens total)

  public static let strategySystem = """
    You choose a coding strategy. Pick the best approach for the task.
    """

  public static func strategyPrompt(query: String, intent: AgentIntent) -> String {
    """
    Task: \(query)
    Domain: \(intent.domain) | Type: \(intent.taskType) | Complexity: \(intent.complexity)
    Targets: \(intent.targets.joined(separator: ", "))
    """
  }

  // MARK: - Plan (~1500 tokens total)

  public static let planSystem = """
    You plan coding tasks as ordered steps. Each step uses exactly one tool. \
    Tools: bash (run commands), read (read file), write (create/overwrite file), \
    edit (find-replace in file), search (grep for pattern). \
    IMPORTANT: Only plan actions the user explicitly asked for. \
    If the user asks to read or explain, do NOT plan edits or writes. \
    If the user asks to fix or add, plan read first, then edit/write. Be minimal.
    """

  public static func planPrompt(
    query: String,
    intent: AgentIntent,
    strategy: AgentStrategy,
    fileContext: String
  ) -> String {
    """
    Task: \(query)
    Domain: \(intent.domain) | Type: \(intent.taskType)
    Strategy: \(strategy.approach)
    Start at: \(strategy.startingPoints.joined(separator: ", "))
    Watch for: \(strategy.risk)
    \(fileContext)
    """
  }

  // MARK: - Execute (~2500 tokens total)

  /// Execute system prompt, with optional domain hint.
  public static func executeSystem(domainHint: String? = nil) -> String {
    var sys = """
      You are a coding agent. Execute the current step by choosing a tool. \
      Tools: bash (shell command), read (file path), write (file path + content), \
      edit (file path + find text + replacement), search (grep pattern). \
      Be precise. Output only the action.
      """
    if let hint = domainHint {
      sys += " \(hint)"
    }
    return sys
  }

  public static func executePrompt(
    step: PlanStep,
    memory: String,
    codeContext: String,
    reflection: String?
  ) -> String {
    var prompt = """
      Step: \(step.instruction)
      Tool hint: \(step.tool) | Target: \(step.target)

      Context:
      \(memory)
      """

    if !codeContext.isEmpty {
      prompt += "\n\nCode:\n\(codeContext)"
    }

    if let reflection, !reflection.isEmpty {
      prompt += "\n\nPast experience: \(reflection)"
    }

    return prompt
  }

  // MARK: - Observe (~1000 tokens total)

  public static let observeSystem = """
    Summarize this tool output concisely. Extract key facts relevant to the task.
    """

  public static func observePrompt(
    tool: String,
    output: String,
    step: String
  ) -> String {
    """
    Tool: \(tool)
    Step: \(step)
    Output:
    \(output)
    """
  }

  // MARK: - Reflect (~1000 tokens total)

  public static let reflectSystem = """
    Reflect on the completed task. What worked? What would you do differently?
    """

  public static func reflectPrompt(memory: WorkingMemory) -> String {
    """
    Task: \(memory.query)
    Steps completed: \(memory.currentStepIndex)
    Errors: \(memory.errors.isEmpty ? "none" : memory.errors.joined(separator: "; "))
    Files touched: \(memory.touchedFiles.sorted().joined(separator: ", "))
    """
  }
}
