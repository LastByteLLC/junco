// Toast.swift — In-TUI notification messages
//
// Styled single-line messages with spacing for readability.
// Errors are prominent (dark red icon, light red message, breathing room).

import Foundation

public enum ToastLevel: Sendable {
  case info, success, warning, error
}

/// Renders styled toast notification lines in the terminal.
public enum Toast {
  /// Show a toast message with appropriate styling and spacing.
  public static func show(_ message: String, level: ToastLevel = .info) {
    switch level {
    case .info:
      Terminal.line(Style.cyan("  \u{2139} ") + Style.dim(message))
    case .success:
      Terminal.line(Style.green("  \u{2713} ") + message)
    case .warning:
      Terminal.line(Style.yellow("  \u{26A0} ") + message)
    case .error:
      // Errors get breathing room and prominent styling
      Terminal.line("")
      Terminal.line(Style.red("  \u{2717} ") + Style.red(message))
      Terminal.line("")
    }
  }

  /// Show an error from a Swift Error type, with human-readable formatting.
  public static func showError(_ error: any Error) {
    show(humanReadable(error), level: .error)
  }

  /// Format a build result as a toast.
  public static func buildResult(_ result: String) {
    if result.contains("FAIL") || result.contains("error") {
      show(result.components(separatedBy: "\n").first ?? result, level: .error)
    } else {
      show(result.components(separatedBy: "\n").first ?? result, level: .success)
    }
  }

  /// Format a timing message.
  public static func timing(_ label: String, seconds: TimeInterval) {
    show("\(label) (\(String(format: "%.1fs", seconds)))", level: .info)
  }

  // MARK: - Human-Readable Error Formatting

  /// Convert a raw Swift error into something a user can understand.
  public static func humanReadable(_ error: any Error) -> String {
    let raw = "\(error)"

    // LLM errors
    if raw.contains("guardrailViolation") {
      return "The on-device model declined this request (safety filter). Try rephrasing."
    }
    if raw.contains("assetsUnavailable") {
      return "Apple Intelligence models not available. Check System Settings > Apple Intelligence."
    }
    if raw.contains("unsupportedLanguageOrLocale") || raw.contains("Unsupported language") {
      return "The on-device model doesn't support this language for structured output. Try the query in English, or download translation models in System Settings > Language & Region > Translation Languages."
    }
    if raw.contains("generationFailed") {
      // Extract the inner message if present
      if let start = raw.range(of: "\""), let end = raw.range(of: "\"", range: start.upperBound..<raw.endIndex) {
        let inner = raw[start.upperBound..<end.lowerBound]
        return "Generation failed: \(inner)"
      }
      return "The on-device model failed to generate a response. Try again or simplify the query."
    }

    // File errors
    if raw.contains("pathOutsideProject") {
      return "File path is outside the project directory."
    }
    if raw.contains("fileNotFound") {
      return "File not found. Check the path and try again."
    }
    if raw.contains("editTextNotFound") {
      return "The text to edit wasn't found in the file. The file may have changed."
    }

    // Shell errors
    if raw.contains("blockedCommand") {
      return "Command blocked for safety. Dangerous operations like rm -rf are not allowed."
    }
    if raw.contains("timeout") {
      return "Command timed out. The operation took too long."
    }

    // Network errors
    if raw.contains("NSURLErrorDomain") || raw.contains("URLError") {
      return "Network error. Check your connection."
    }

    // Fallback: clean up the raw error
    return raw
      .replacingOccurrences(of: "JuncoKit.", with: "")
      .replacingOccurrences(of: "LLMError.", with: "")
      .replacingOccurrences(of: "OrchestratorError.", with: "")
      .replacingOccurrences(of: "FileToolError.", with: "")
      .replacingOccurrences(of: "ShellError.", with: "")
  }
}
