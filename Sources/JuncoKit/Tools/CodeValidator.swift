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
      JSCValidator(),
      SwiftValidator(),
      HTMLValidator(),
      CSSValidator(),
      JSONValidator(),
      ShellScriptValidator(),
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

// MARK: - HTML Validator

/// Validates HTML structure: balanced tags, required elements, basic well-formedness.
public struct HTMLValidator: CodeValidator, Sendable {
  public var supportedExtensions: Set<String> { ["html", "htm"] }

  public init() {}

  public func validate(code: String, filePath: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "HTML error: empty file content."
    }

    // Check for basic HTML structure
    let lower = trimmed.lowercased()
    if !lower.contains("<html") && !lower.contains("<!doctype") {
      // Could be an HTML fragment — validate tag balance only
    }

    // Stack-based tag balance check
    var tagStack: [String] = []
    let voidElements: Set<String> = [
      "area", "base", "br", "col", "embed", "hr", "img", "input",
      "link", "meta", "param", "source", "track", "wbr",
    ]
    var i = trimmed.startIndex
    while i < trimmed.endIndex {
      if trimmed[i] == "<" {
        guard let closeAngle = trimmed[i...].firstIndex(of: ">") else {
          return "HTML error: unclosed < bracket in \(filePath)"
        }
        let tagContent = String(trimmed[trimmed.index(after: i)..<closeAngle])
          .trimmingCharacters(in: .whitespaces)

        if tagContent.hasPrefix("!") || tagContent.hasPrefix("?") {
          // Comment, doctype, or processing instruction — skip
        } else if tagContent.hasPrefix("/") {
          // Closing tag
          let tagName = String(tagContent.dropFirst())
            .split(separator: " ").first.map { String($0).lowercased() } ?? ""
          if let last = tagStack.last, last == tagName {
            tagStack.removeLast()
          } else if !tagStack.isEmpty {
            let expected = tagStack.last ?? "none"
            return "HTML error: expected </\(expected)> but found </\(tagName)> in \(filePath)"
          }
        } else {
          // Opening tag
          let tagName = tagContent
            .split(separator: " ").first.map { String($0).lowercased() } ?? ""
          let cleanName = tagName.replacingOccurrences(of: "/", with: "")
          if !cleanName.isEmpty && !voidElements.contains(cleanName) &&
             !tagContent.hasSuffix("/") {
            tagStack.append(cleanName)
          }
        }
        i = trimmed.index(after: closeAngle)
      } else {
        i = trimmed.index(after: i)
      }
    }

    if !tagStack.isEmpty {
      return "HTML error: unclosed tags: \(tagStack.joined(separator: ", ")) in \(filePath)"
    }

    return nil
  }
}

// MARK: - CSS Validator

/// Validates CSS structure: balanced braces, basic property syntax.
public struct CSSValidator: CodeValidator, Sendable {
  public var supportedExtensions: Set<String> { ["css"] }

  public init() {}

  public func validate(code: String, filePath: String) -> String? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "CSS error: empty file content."
    }

    // Check balanced braces
    var braceDepth = 0
    var parenDepth = 0
    var inString = false
    var stringChar: Character = "\""
    var lineNumber = 1

    for (idx, ch) in trimmed.enumerated() {
      if ch == "\n" { lineNumber += 1 }

      if inString {
        if ch == stringChar && (idx == 0 || trimmed[trimmed.index(trimmed.startIndex, offsetBy: idx - 1)] != "\\") {
          inString = false
        }
        continue
      }

      switch ch {
      case "\"", "'":
        inString = true
        stringChar = ch
      case "{":
        braceDepth += 1
      case "}":
        braceDepth -= 1
        if braceDepth < 0 {
          return "CSS error: unexpected } at line \(lineNumber) in \(filePath)"
        }
      case "(":
        parenDepth += 1
      case ")":
        parenDepth -= 1
        if parenDepth < 0 {
          return "CSS error: unexpected ) at line \(lineNumber) in \(filePath)"
        }
      default:
        break
      }
    }

    if braceDepth != 0 {
      return "CSS error: \(braceDepth) unclosed { brace(s) in \(filePath)"
    }
    if parenDepth != 0 {
      return "CSS error: \(parenDepth) unclosed ( parenthesis in \(filePath)"
    }

    // Check for HTML tags accidentally written in CSS
    if trimmed.contains("<html") || trimmed.contains("<link") || trimmed.contains("<!DOCTYPE") {
      return "CSS error: file contains HTML tags instead of CSS in \(filePath)"
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
    let errPipe = Pipe()
    process.standardError = errPipe
    process.standardOutput = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil // Can't validate — don't block
    }

    guard process.terminationStatus != 0 else { return nil }

    let stderr = String(
      data: errPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let errors = stderr.components(separatedBy: "\n")
      .filter { $0.contains("syntax error") || $0.contains("unexpected") }
      .prefix(3)
      .joined(separator: "\n")
    return errors.isEmpty ? nil : "Shell syntax error: \(errors). Fix and regenerate."
  }
}
