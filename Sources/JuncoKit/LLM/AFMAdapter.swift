// AFMAdapter.swift — Apple Foundation Models backend
//
// Each call creates a fresh LanguageModelSession (lightweight, not designed for reuse
// across unrelated prompts). Always uses `.default` — LoRA loading was removed due to
// an Apple-confirmed APFS metadata leak on current macOS (~100MB/call); see Apple
// Forums thread 823001. Do not re-introduce LoRA loading until Apple ships a fix.

import Foundation
import FoundationModels

public actor AFMAdapter: LLMAdapter {

  nonisolated public let backendName = "Apple Foundation Models (Neural Engine)"
  nonisolated public let isAFM = true

  public init() {}

  // MARK: - Pre-warming

  public func prewarm() async {
    let session = makeSession(instructions: nil, tools: [])
    session.prewarm()
  }

  public func prewarm(systemPrompt: String) async {
    let session = makeSession(instructions: AFMInstructions.fromString(systemPrompt), tools: [])
    session.prewarm()
  }

  // MARK: - Session factory

  private func systemModel() -> FoundationModels.SystemLanguageModel { .default }

  // MARK: - Per-call timeout

  /// Hard ceiling on a single AFM generation call. AFM occasionally stalls on
  /// specific prompts (observed inside CVF loops for some create/edit cases).
  /// Without this ceiling, hangs propagate up and block the whole pipeline.
  /// 120s is well above the 99th-percentile legitimate call duration observed in evals.
  private let perCallTimeoutSec: Double = 120

  /// Run `body` with a per-call timeout. If the deadline is exceeded, cancels the
  /// work and throws `LLMError.generationFailed("AFM timeout after Ns")`. The wrapped
  /// session call may itself be un-cancellable; the timeout at least unblocks callers.
  private func withAFMTimeout<T: Sendable>(_ body: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await body() }
      group.addTask { [perCallTimeoutSec] in
        try await Task.sleep(nanoseconds: UInt64(perCallTimeoutSec * 1_000_000_000))
        throw LLMError.generationFailed("AFM timeout after \(Int(perCallTimeoutSec))s")
      }
      guard let result = try await group.next() else {
        throw LLMError.generationFailed("AFM timeout task group empty")
      }
      group.cancelAll()
      return result
    }
  }

  private func makeSession(
    instructions: Instructions?,
    tools: [any FoundationModels.Tool]
  ) -> FoundationModels.LanguageModelSession {
    let model = systemModel()
    switch (instructions, tools.isEmpty) {
    case (let inst?, true):
      return FoundationModels.LanguageModelSession(model: model, instructions: inst)
    case (let inst?, false):
      return FoundationModels.LanguageModelSession(model: model, tools: tools, instructions: inst)
    case (nil, true):
      return FoundationModels.LanguageModelSession(model: model)
    case (nil, false):
      return FoundationModels.LanguageModelSession(model: model, tools: tools)
    }
  }

  // MARK: - Plain text generation

  public func generate(prompt: String, system: String?) async throws -> String {
    try await generate(prompt: prompt, system: system, tools: [])
  }

  /// Text generation with optional native AFM tools.
  /// The model may call tools during generation; their schemas are injected into
  /// the session's instructions automatically (via Tool.includesSchemaInInstructions).
  public func generate(
    prompt: String,
    system: String?,
    tools: [any FoundationModels.Tool]
  ) async throws -> String {
    let safeSystem = system ?? ""
    let (compactSystem, compactPrompt) = await TokenGuard.compact(
      system: safeSystem,
      prompt: prompt,
      adapter: self,
      reserveForGeneration: 2500,
      schemaOverhead: 0
    )

    let instructions = compactSystem.isEmpty ? nil : AFMInstructions.fromString(compactSystem)
    let session = makeSession(instructions: instructions, tools: tools)

    do {
      return try await withAFMTimeout {
        try await session.respond(to: compactPrompt).content
      }
    } catch let error as FoundationModels.LanguageModelSession.GenerationError {
      throw mapError(error)
    }
  }

  // MARK: - Streaming text generation

  public func generateStreaming(
    prompt: String,
    system: String?,
    onChunk: @escaping @Sendable (String) async -> Void
  ) async throws -> String {
    let instructions = AFMInstructions.fromString(system)
    let session = makeSession(instructions: instructions, tools: [])

    do {
      var fullText = ""
      let stream = session.streamResponse(to: prompt)
      for try await partial in stream {
        let newContent = partial.content
        if newContent.count > fullText.count {
          let delta = String(newContent.dropFirst(fullText.count))
          await onChunk(delta)
        }
        fullText = newContent
      }
      return fullText
    } catch let error as FoundationModels.LanguageModelSession.GenerationError {
      throw mapError(error)
    }
  }

  // MARK: - Structured generation

  public func generateStructured<T: GenerableContent>(
    prompt: String,
    system: String?,
    as type: T.Type,
    options: LLMGenerationOptions? = nil
  ) async throws -> T {
    try await generateStructured(prompt: prompt, system: system, tools: [], as: type, options: options)
  }

  /// Structured generation with optional native AFM tools.
  public func generateStructured<T: GenerableContent>(
    prompt: String,
    system: String?,
    tools: [any FoundationModels.Tool],
    as type: T.Type,
    options: LLMGenerationOptions? = nil
  ) async throws -> T {
    let safeSystem = system ?? ""
    let (compactSystem, compactPrompt) = await TokenGuard.compact(
      system: safeSystem,
      prompt: prompt,
      adapter: self,
      reserveForGeneration: 800,
      schemaOverhead: 150
    )

    let instructions = compactSystem.isEmpty ? nil : AFMInstructions.fromString(compactSystem)
    let session = makeSession(instructions: instructions, tools: tools)

    do {
      return try await withAFMTimeout {
        if let options {
          let fmOpts = options.toFoundationModels()
          return try await session.respond(to: compactPrompt, generating: type, options: fmOpts).content
        } else {
          return try await session.respond(to: compactPrompt, generating: type).content
        }
      }
    } catch let error as FoundationModels.LanguageModelSession.GenerationError {
      throw mapError(error)
    }
  }

  // MARK: - Token counting

  public func countTokens(_ text: String) async -> Int {
    #if compiler(>=6.3)
    if #available(macOS 26.4, iOS 26.4, *) {
      return (try? await systemModel().tokenCount(for: text)) ?? AFMTokenEstimator.countTokens(text)
    }
    #endif
    return AFMTokenEstimator.countTokens(text)
  }

  /// Max context window in tokens. Derived from the live SystemLanguageModel —
  /// `contextSize` is @backDeployed(before: macOS 26.4), so it's callable on 26.0+
  /// when built with Swift 6.3 SDK. A user may override it via
  /// $META_CONFIG_JSON (contextWindow key) for A/B testing.
  public var contextSize: Int {
    if let override = MetaConfig.shared.contextWindow { return override }
    #if compiler(>=6.3)
    return systemModel().contextSize
    #else
    return 4096
    #endif
  }

  // MARK: - Error mapping

  private func mapError(_ error: FoundationModels.LanguageModelSession.GenerationError) -> LLMError {
    switch error {
    case .guardrailViolation:
      return .guardrailViolation
    case .assetsUnavailable:
      return .unavailable("On-device model assets not downloaded. Check Settings > Apple Intelligence.")
    case .exceededContextWindowSize(let context):
      return .contextOverflow(context.debugDescription)
    default:
      return .generationFailed(error.localizedDescription)
    }
  }
}

// MARK: - Options bridging

extension LLMGenerationOptions {
  func toFoundationModels() -> FoundationModels.GenerationOptions {
    var opts = FoundationModels.GenerationOptions()
    if let maximumResponseTokens { opts.maximumResponseTokens = maximumResponseTokens }
    if let temperature { opts.temperature = temperature }
    if let sampling {
      switch sampling {
      case .greedy:
        opts.sampling = .greedy
      case .random(let topK, let topP, let seed):
        // topK wins if both are set — AFM accepts either top-K or probability threshold, not both.
        if let topK {
          opts.sampling = .random(top: topK, seed: seed)
        } else if let topP {
          opts.sampling = .random(probabilityThreshold: topP, seed: seed)
        }
        // Both nil: leave sampling unset → AFM default (implicit temperature-based sampling).
      }
    }
    return opts
  }
}

// MARK: - Typealias for @Generable conformance requirement

/// Types that can be generated must conform to this.
/// Requires Generable (for AFM structured output), Codable (for Ollama JSON decoding), and Sendable.
public typealias GenerableContent = FoundationModels.Generable & Codable & Sendable
