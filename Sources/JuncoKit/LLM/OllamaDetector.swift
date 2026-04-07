// OllamaDetector.swift — Auto-detect Ollama installation and running models

import Foundation

/// Detect whether Ollama is installed, running, and which models are available.
public struct OllamaDetector: Sendable {

  /// Default Ollama server URL.
  public static let defaultHost = "http://localhost:11434"

  /// Check if the `ollama` CLI is installed.
  public static func isInstalled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["ollama"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  /// Check if the Ollama server is reachable by hitting GET /api/tags.
  /// Returns true if the server responds within 2 seconds.
  public static func isRunning(host: String = defaultHost) async -> Bool {
    guard let url = URL(string: "\(host)/api/tags") else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  /// List locally available models from the Ollama server.
  public static func availableModels(host: String = defaultHost) async -> [OllamaModel] {
    guard let url = URL(string: "\(host)/api/tags") else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
      let parsed = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
      return parsed.models.map { model in
        OllamaModel(
          name: model.name,
          size: model.size,
          parameterSize: model.details?.parameterSize
        )
      }
    } catch {
      return []
    }
  }

  /// Pick the best coding model from available models.
  /// Prefers: qwen2.5-coder > codellama > deepseek-coder > qwen > llama > first available.
  public static func bestCodingModel(from models: [OllamaModel]) -> OllamaModel? {
    guard !models.isEmpty else { return nil }

    let preferences = [
      "qwen2.5-coder",
      "qwen3",
      "codellama",
      "deepseek-coder",
      "codegemma",
      "qwen2.5",
      "qwen2",
      "llama3",
      "llama",
      "mistral",
      "gemma"
    ]

    for prefix in preferences {
      if let match = models.first(where: { $0.name.lowercased().hasPrefix(prefix) }) {
        return match
      }
    }
    return models.first
  }

  /// List models currently loaded in Ollama's memory (GET /api/ps).
  /// These models are warm and ready for instant inference.
  public static func runningModels(host: String = defaultHost) async -> [OllamaModel] {
    guard let url = URL(string: "\(host)/api/ps") else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
      let parsed = try JSONDecoder().decode(OllamaPsResponse.self, from: data)
      return parsed.models.map { model in
        OllamaModel(
          name: model.name,
          size: model.size ?? 0,
          parameterSize: model.details?.parameterSize
        )
      }
    } catch {
      return []
    }
  }

  /// Full auto-detection: prefer the currently-running model, then fall back to
  /// preference-ranked selection from downloaded models.
  /// Returns nil if Ollama is not available.
  public static func autoDetect(host: String = defaultHost) async -> OllamaModel? {
    guard await isRunning(host: host) else { return nil }

    // Prefer a model already loaded in memory — it's warm and ready
    let running = await runningModels(host: host)
    if let active = running.first {
      return active
    }

    // Nothing loaded — pick from downloaded models by preference
    let models = await availableModels(host: host)
    return bestCodingModel(from: models)
  }

  /// Query the actual context window size for a model via POST /api/show.
  /// Returns nil if the query fails; caller should fall back to a sensible default.
  public static func contextSize(for modelName: String, host: String = defaultHost) async -> Int? {
    guard let url = URL(string: "\(host)/api/show") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 5
    request.httpBody = try? JSONEncoder().encode(["name": modelName])

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

      // The response has model_info with context length, or parameters with num_ctx
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        // Check model_info for architecture-level context length
        if let modelInfo = json["model_info"] as? [String: Any] {
          // Keys vary by architecture but typically end in ".context_length"
          for (key, value) in modelInfo {
            if key.contains("context_length"), let ctx = value as? Int, ctx > 0 {
              return ctx
            }
          }
        }
        // Check parameters string for num_ctx
        if let params = json["parameters"] as? String {
          for line in params.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("num_ctx") {
              let parts = trimmed.split(separator: " ")
              if parts.count >= 2, let ctx = Int(parts.last ?? "") {
                return ctx
              }
            }
          }
        }
      }
      return nil
    } catch {
      return nil
    }
  }
}

// MARK: - Models

/// A locally available Ollama model.
public struct OllamaModel: Sendable {
  public let name: String
  public let size: Int64
  public let parameterSize: String?

  public init(name: String, size: Int64, parameterSize: String?) {
    self.name = name
    self.size = size
    self.parameterSize = parameterSize
  }

  /// Human-readable size (e.g., "4.1 GB").
  public var formattedSize: String {
    let gb = Double(size) / 1_073_741_824
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(size) / 1_048_576
    return String(format: "%.0f MB", mb)
  }
}

// MARK: - API Response Types

private struct OllamaTagsResponse: Decodable {
  let models: [OllamaTagModel]
}

private struct OllamaTagModel: Decodable {
  let name: String
  let size: Int64
  let details: OllamaModelDetails?
}

private struct OllamaPsResponse: Decodable {
  let models: [OllamaPsModel]
}

private struct OllamaPsModel: Decodable {
  let name: String
  let size: Int64?
  let details: OllamaModelDetails?
}

private struct OllamaModelDetails: Decodable {
  let parameterSize: String?

  enum CodingKeys: String, CodingKey {
    case parameterSize = "parameter_size"
  }
}
