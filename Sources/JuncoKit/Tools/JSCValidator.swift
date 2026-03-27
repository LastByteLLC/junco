// JSCValidator.swift — JavaScriptCore-based validation for generated JavaScript
//
// Validates junco-generated JS code before writing to disk:
// 1. Syntax check (instant, catches malformed code)
// 2. Runtime execution (catches TypeError, ReferenceError, etc.)
// 3. Test assertions (if test code provided)
//
// This creates a tight feedback loop: generate → validate → fix → write.
// Integrated into the orchestrator's write/edit path for .js/.ts files.

import Foundation
import JavaScriptCore

/// Result of JavaScript validation.
public struct JSValidationResult: Sendable {
  public let valid: Bool
  public let error: String?
  public let output: String?

  public static func success(output: String? = nil) -> JSValidationResult {
    JSValidationResult(valid: true, error: nil, output: output)
  }

  public static func failure(_ error: String) -> JSValidationResult {
    JSValidationResult(valid: false, error: error, output: nil)
  }
}

/// Validates JavaScript code using JavaScriptCore.
/// Thread-safe: creates a fresh JSContext per validation (lightweight).
public struct JSCValidator: Sendable {
  public init() {}

  /// Validate JS code for syntax and runtime errors.
  /// Optionally run test assertions against the code.
  public func validate(
    code: String,
    testCode: String? = nil
  ) -> JSValidationResult {
    let ctx = JSContext()!
    var caughtError: String?

    // Capture exceptions
    ctx.exceptionHandler = { _, exception in
      caughtError = exception?.toString()
    }

    // Provide console.log
    var logs: [String] = []
    let logFn: @convention(block) (String) -> Void = { msg in logs.append(msg) }
    ctx.setObject(logFn, forKeyedSubscript: "log" as NSString)
    ctx.evaluateScript("var console = { log: log, error: log, warn: log, info: log }")

    // Provide minimal globals that generated code might reference
    ctx.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
    ctx.evaluateScript("var global = this; var globalThis = this;")
    ctx.evaluateScript("var process = { env: {} };")

    // Phase 1: Syntax + runtime check
    ctx.evaluateScript(code)
    if let err = caughtError {
      return .failure(err)
    }

    // Phase 2: Run test assertions
    if let testCode {
      caughtError = nil
      ctx.evaluateScript(testCode)
      if let err = caughtError {
        return .failure("Test assertion: \(err)")
      }
    }

    let output = logs.isEmpty ? nil : logs.joined(separator: "\n")
    return .success(output: output)
  }

  /// Quick syntax-only check (doesn't execute the code).
  /// Uses Function constructor to parse without running.
  public func checkSyntax(_ code: String) -> JSValidationResult {
    let ctx = JSContext()!
    var caughtError: String?

    ctx.exceptionHandler = { _, exception in
      caughtError = exception?.toString()
    }

    // Wrap in Function() to check syntax without executing
    ctx.evaluateScript("new Function(\(escapeForJS(code)))")
    if let err = caughtError {
      return .failure(err)
    }
    return .success()
  }

  /// Validate and generate a feedback string for the LLM.
  /// Returns nil if code is valid, or an error description for re-generation.
  public func feedbackForLLM(code: String, filePath: String) -> String? {
    let ext = (filePath as NSString).pathExtension
    guard ["js", "jsx", "ts", "tsx", "mjs", "cjs"].contains(ext) else { return nil }

    // TypeScript can't be validated directly — check syntax only
    if ext == "ts" || ext == "tsx" {
      let result = checkSyntax(code)
      if !result.valid {
        return "JavaScript syntax error in generated code: \(result.error ?? "unknown"). Fix and regenerate."
      }
      return nil
    }

    let result = validate(code: code)
    if !result.valid {
      return "JavaScript error in generated code: \(result.error ?? "unknown"). Fix and regenerate."
    }
    return nil
  }

  private func escapeForJS(_ code: String) -> String {
    let escaped = code
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
    return "'\(escaped)'"
  }
}
