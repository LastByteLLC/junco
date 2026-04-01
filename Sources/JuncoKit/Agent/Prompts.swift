// Prompts.swift — Ultra-compact prompt templates for each pipeline stage
//
// Every prompt is designed to fit within its stage's token budget.
// Tool list is consistent across plan + execute stages.

/// Central tool description used in both plan and execute prompts.
private let toolList = """
  bash (run shell command), read (read file), create (create new file), \
  write (overwrite existing file), edit (find-replace in file), \
  patch (apply unified diff), search (grep pattern)
  """

/// Prompt templates for each pipeline stage.
public enum Prompts {

  // MARK: - Classify

  public static let classifySystem = """
    You classify coding tasks. Respond with the structured fields only.
    """

  public static func classifyPrompt(query: String, fileHints: String) -> String {
    """
    Query: \(query)
    Project files: \(fileHints)
    """
  }

  // MARK: - Strategy

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

  // MARK: - Plan

  public static let planSystem = """
    You plan coding tasks as ordered steps. Each step uses exactly one tool. \
    Tools: \(toolList). \
    IMPORTANT: Only plan actions the user explicitly asked for. \
    If the user asks to read or explain, do NOT plan edits or writes. \
    If the user asks to fix existing code, read the file first, then edit. \
    If the user asks to create a new file, use create (not write, not edit). \
    Use the fewest steps possible. For creating one file, plan one create step.
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

  // MARK: - Observe

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

  // MARK: - Reflect

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
