// ExemplarRetriever.swift — Few-shot exemplar retrieval for code generation
//
// Retrieves relevant code examples for prompt injection:
// 1. Search project index for similar completed files (same role, shared types)
// 2. Compress best match via ProgressiveCompressor.codeGist()
// 3. Fall back to built-in exemplars cached at ~/.junco/exemplars/
//
// Built-in exemplars are fetched from GitHub on first run.

import Foundation

/// Retrieves relevant code examples for few-shot prompt injection.
public struct ExemplarRetriever: Sendable {

  /// GitHub raw URL base for fetching built-in exemplars.
  private let githubBase: String
  /// Local cache directory for built-in exemplars.
  private let cacheDir: String

  public init(
    githubBase: String = "https://raw.githubusercontent.com/nicholasgasior/junco/master/Sources/JuncoKit/Resources/exemplars",
    cacheDir: String? = nil
  ) {
    self.githubBase = githubBase
    self.cacheDir = cacheDir ?? "\(Config.globalDir)/exemplars"
  }

  // MARK: - Public API

  /// Retrieve the best exemplar for a target file.
  /// Tries project files first, then built-in exemplars.
  /// Returns a compressed code snippet suitable for prompt injection (~150-200 tokens).
  public func retrieve(
    targetPath: String,
    role: String,
    snapshot: ProjectSnapshot,
    index: [IndexEntry],
    compressor: ProgressiveCompressor,
    fileReader: FileTools? = nil
  ) async -> String? {
    // Strategy 1: Find a similar file in the project
    if let reader = fileReader,
       let similarPath = findSimilarFile(role: role, targetPath: targetPath, index: index),
       let content = try? reader.read(path: similarPath, maxTokens: 400) {
      let gist = compressor.codeGistAST(content) ?? compressor.codeGist(content)
      if TokenBudget.estimate(gist) <= 200 && !gist.isEmpty {
        return "// Reference pattern from \((similarPath as NSString).lastPathComponent):\n\(gist)"
      }
    }

    // Strategy 2: Load a built-in exemplar for this role
    if let exemplar = await loadBuiltInExemplar(for: role) {
      return "// Reference pattern:\n\(exemplar)"
    }

    return nil
  }

  // MARK: - Project File Matching

  /// Find the most similar existing file in the project by role.
  func findSimilarFile(role: String, targetPath: String, index: [IndexEntry]) -> String? {
    // Get unique file paths that aren't the target
    let targetName = (targetPath as NSString).lastPathComponent
    let candidates = Set(index.map(\.filePath))
      .filter { path in
        let name = (path as NSString).lastPathComponent
        return name != targetName && name.hasSuffix(".swift")
      }

    // Score each candidate by role match
    var bestPath: String?
    var bestScore = 0

    for path in candidates {
      let candidateRole = inferRole(path)
      var score = 0

      // Same role is the strongest signal
      if candidateRole == role { score += 10 }

      // Bonus for similar category (both are "views", both are "models", etc.)
      if roleCategory(candidateRole) == roleCategory(role) { score += 5 }

      // Bonus for having symbols (not empty/stub files)
      let symbolCount = index.filter { $0.filePath == path && $0.kind != .file && $0.kind != .import }.count
      if symbolCount >= 2 { score += 3 }

      if score > bestScore {
        bestScore = score
        bestPath = path
      }
    }

    // Only return if we have a reasonable match
    return bestScore >= 5 ? bestPath : nil
  }

  // MARK: - Built-In Exemplars

  /// Load a built-in exemplar from cache (or fall back to bundled list).
  func loadBuiltInExemplar(for role: String) async -> String? {
    // Map role to exemplar filenames
    let candidates = exemplarFilenames(for: role)
    guard !candidates.isEmpty else { return nil }

    // Try loading from cache
    for filename in candidates {
      let path = (cacheDir as NSString).appendingPathComponent(filename)
      if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    // Try fetching from GitHub if cache miss
    await ensureCached(filenames: candidates)

    // Retry from cache after fetch
    for filename in candidates {
      let path = (cacheDir as NSString).appendingPathComponent(filename)
      if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    return nil
  }

  /// Ensure exemplar files are cached locally.
  /// Downloads from GitHub raw content on first run.
  public func ensureCached(filenames: [String]? = nil) async {
    // Create cache dir if needed
    try? FileManager.default.createDirectory(
      atPath: cacheDir, withIntermediateDirectories: true
    )

    let targets = filenames ?? Self.allExemplarFilenames
    for filename in targets {
      let localPath = (cacheDir as NSString).appendingPathComponent(filename)
      // Skip if already cached
      if FileManager.default.fileExists(atPath: localPath) { continue }

      // Fetch from GitHub
      let urlString = "\(githubBase)/\(filename)"
      guard let url = URL(string: urlString) else { continue }

      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else { continue }
        try content.write(toFile: localPath, atomically: true, encoding: .utf8)
      } catch {
        continue // Silently skip — exemplars are optional
      }
    }
  }

  // MARK: - Role Mapping

  /// Map file roles to exemplar filenames (ordered by relevance).
  func exemplarFilenames(for role: String) -> [String] {
    switch role {
    case "view":
      return ["view_list_navigation.swift", "view_search.swift", "view_detail.swift"]
    case "viewmodel":
      return ["viewmodel_observable.swift", "viewmodel_pagination.swift"]
    case "service":
      return ["service_url_session.swift", "service_url_components.swift"]
    case "model":
      return ["model_codable_struct.swift", "model_enum_associated.swift"]
    case "test":
      return ["test_basic.swift", "test_async.swift"]
    case "app":
      return ["app_main.swift", "app_tabview.swift"]
    default:
      return ["basics_protocols.swift", "model_codable_struct.swift"]
    }
  }

  /// Infer file role from path (mirrors MicroSkill.inferFileRole).
  private func inferRole(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent.lowercased()
    if name.contains("view") && !name.contains("viewmodel") { return "view" }
    if name.contains("viewmodel") || name.contains("store") { return "viewmodel" }
    if name.contains("service") || name.contains("client") || name.contains("api") { return "service" }
    if name.contains("test") { return "test" }
    if name.contains("app") && name.hasSuffix("app.swift") { return "app" }
    return "model"
  }

  /// Group roles into categories for partial matching.
  private func roleCategory(_ role: String) -> String {
    switch role {
    case "view", "viewmodel": return "ui"
    case "service", "model": return "data"
    case "test": return "test"
    case "app": return "app"
    default: return "other"
    }
  }

  // MARK: - Manifest

  /// All built-in exemplar filenames.
  static let allExemplarFilenames = [
    // Models
    "model_codable_struct.swift", "model_enum_associated.swift",
    "model_codable_nested.swift", "model_identifiable_hashable.swift",
    "model_result_type.swift", "model_codable_enum.swift",
    // Services
    "service_url_session.swift", "service_url_components.swift",
    "service_cache.swift", "service_error_handling.swift",
    // ViewModels
    "viewmodel_observable.swift", "viewmodel_pagination.swift", "viewmodel_form.swift",
    // Views
    "view_list_navigation.swift", "view_detail.swift", "view_form_input.swift",
    "view_search.swift", "view_sheet_alert.swift", "view_custom_modifier.swift",
    // App
    "app_main.swift", "app_tabview.swift",
    // Tests
    "test_basic.swift", "test_async.swift", "test_parameterized.swift",
    // Concurrency
    "concurrency_actor.swift", "concurrency_taskgroup.swift", "concurrency_sendable.swift",
    // Basics
    "basics_optionals.swift", "basics_closures.swift", "basics_protocols.swift",
    "basics_generics.swift", "basics_error_handling.swift", "basics_control_flow.swift",
    // SwiftData
    "swiftdata_model.swift", "swiftdata_query.swift"
  ]
}
