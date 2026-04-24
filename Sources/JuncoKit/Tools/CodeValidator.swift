// CodeValidator.swift — Generic validation framework for generated code
//
// Each language gets a validator that checks syntax/structure BEFORE writing
// to disk. Validators are registered by file extension and run automatically
// in the create/write pipeline.
//
// Validators MUST be:
//   - Fast (< 1 second)
//   - Zero external dependencies (stock macOS only)
//   - Non-destructive (never modify the input)

import Foundation

/// Protocol for language-specific code validators.
/// Return nil if code is valid, or an error description for LLM feedback.
public protocol CodeValidator: Sendable {
  /// File extensions this validator handles (without dots, e.g. "swift", "js").
  var supportedExtensions: Set<String> { get }

  /// Validate code for the given file path.
  /// Returns nil if valid, or an error string suitable for LLM retry prompts.
  func validate(code: String, filePath: String) -> String?
}

/// Registry that dispatches validation to the right validator by file extension.
public struct ValidatorRegistry: Sendable {
  private let validators: [CodeValidator]

  public init(validators: [CodeValidator]) {
    self.validators = validators
  }

  /// Default registry with all built-in validators.
  public static func `default`() -> ValidatorRegistry {
    ValidatorRegistry(validators: [
      SwiftValidator(),
      JSONValidator(),
      ShellScriptValidator()
    ])
  }

  /// Validate code for a file path. Returns nil if valid or no validator matches.
  public func validate(code: String, filePath: String) -> String? {
    let ext = (filePath as NSString).pathExtension.lowercased()
    for validator in validators {
      if validator.supportedExtensions.contains(ext) {
        return validator.validate(code: code, filePath: filePath)
      }
    }
    return nil
  }
}

// MARK: - JSON Validator

/// Validates JSON syntax using Foundation's JSONSerialization.
public struct JSONValidator: CodeValidator, Sendable {
  public var supportedExtensions: Set<String> { ["json"] }

  public init() {}

  public func validate(code: String, filePath: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "JSON error: empty file content."
    }
    guard let data = trimmed.data(using: .utf8) else {
      return "JSON error: invalid UTF-8 encoding in \(filePath)"
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
      return nil
    } catch {
      return "JSON syntax error in \(filePath): \(error.localizedDescription). Fix and regenerate."
    }
  }
}

// MARK: - Shell Script Validator

/// Validates shell script syntax using bash -n (parse without execution).
public struct ShellScriptValidator: CodeValidator, Sendable {
  public var supportedExtensions: Set<String> { ["sh", "bash", "zsh"] }

  public init() {}

  public func validate(code: String, filePath: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "Shell script error: empty file content."
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-n", "-c", trimmed]
    // File redirect rather than Pipe: avoids the kernel-buffer deadlock that surfaced
    // in SwiftValidator / SafeShell (pipe fills → child blocks → waitUntilExit hangs).
    let errPath = NSTemporaryDirectory() + "junco-shcheck-err-\(UUID().uuidString).log"
    guard FileManager.default.createFile(atPath: errPath, contents: nil),
          let errHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: errPath)) else {
      return nil
    }
    defer {
      try? errHandle.close()
      try? FileManager.default.removeItem(atPath: errPath)
    }
    process.standardError = errHandle
    process.standardOutput = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil // Can't validate — don't block
    }

    guard process.terminationStatus != 0 else { return nil }

    try? errHandle.close()
    let errData = (try? Data(contentsOf: URL(fileURLWithPath: errPath))) ?? Data()
    let stderr = String(data: errData, encoding: .utf8) ?? ""
    let errors = stderr.components(separatedBy: "\n")
      .filter { $0.contains("syntax error") || $0.contains("unexpected") }
      .prefix(3)
      .joined(separator: "\n")
    return errors.isEmpty ? nil : "Shell syntax error: \(errors). Fix and regenerate."
  }
}
