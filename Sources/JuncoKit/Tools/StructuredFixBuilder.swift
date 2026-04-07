// StructuredFixBuilder.swift — Pattern-match compiler errors to structured fixes
//
// Analyzes swiftc error messages and builds targeted fix instructions.
// For deterministic patterns (.exact confidence), the fix can be applied
// without any LLM call. For likely patterns, the fix enriches the LLM prompt.

import Foundation

/// A structured fix instruction derived from a compiler error.
public struct FixInstruction: Sendable {
  /// The line number in the original file.
  public let line: Int
  /// Human-readable description of what to change.
  public let description: String
  /// Exact replacement text, if the fix is deterministic.
  public let replacement: String?
  /// How confident we are in this fix.
  public let confidence: Confidence

  public enum Confidence: Sendable {
    /// Can be applied directly without LLM call.
    case exact
    /// Strong hint — model should follow this instruction.
    case likely
    /// Contextual information only.
    case hint
  }
}

/// Builds structured fix instructions from compiler errors and API knowledge.
public struct StructuredFixBuilder: Sendable {

  public init() {}

  /// Build a fix instruction from a compiler error.
  /// Returns nil if no pattern matches.
  public func buildFixInstruction(
    error: BuildError,
    codeRegion: CodeRegion,
    apiHint: String?,
    snapshot: ProjectSnapshot
  ) -> FixInstruction? {
    let msg = error.message

    // Try each pattern in order of specificity
    if let fix = matchRedundantConformance(msg, region: codeRegion, line: error.line) { return fix }
    if let fix = matchIncorrectLabel(msg, region: codeRegion, line: error.line) { return fix }
    if let fix = matchExtraArgument(msg, region: codeRegion, line: error.line) { return fix }
    if let fix = matchNoMember(msg, region: codeRegion, line: error.line, snapshot: snapshot, apiHint: apiHint) { return fix }
    if let fix = matchTypeMismatch(msg, line: error.line, apiHint: apiHint) { return fix }
    if let fix = matchMissingArgument(msg, line: error.line, apiHint: apiHint) { return fix }
    if let fix = matchUseOfUnresolved(msg, line: error.line) { return fix }

    return nil
  }

  // MARK: - Pattern: Redundant Conformance

  /// `redundant conformance of 'X' to protocol 'Y'`
  private func matchRedundantConformance(_ msg: String, region: CodeRegion, line: Int) -> FixInstruction? {
    let pattern = #"redundant conformance of '(\w+)' to protocol '(\w+)'"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let protocolRange = Range(match.range(at: 2), in: msg) else { return nil }

    let protocolName = String(msg[protocolRange])

    // Find and remove `: ProtocolName` or `, ProtocolName` from the declaration line
    let regionLines = region.text.components(separatedBy: "\n")
    let targetLineIdx = line - 1 - region.startLine
    guard targetLineIdx >= 0, targetLineIdx < regionLines.count else {
      return FixInstruction(
        line: line,
        description: "Remove redundant conformance to '\(protocolName)'",
        replacement: nil,
        confidence: .likely
      )
    }

    var fixedLine = regionLines[targetLineIdx]
    // Try removing ", ProtocolName" first, then ": ProtocolName"
    fixedLine = fixedLine.replacingOccurrences(of: ", \(protocolName)", with: "")
    fixedLine = fixedLine.replacingOccurrences(of: ": \(protocolName),", with: ":")
    fixedLine = fixedLine.replacingOccurrences(of: ": \(protocolName) ", with: " ")

    if fixedLine != regionLines[targetLineIdx] {
      return FixInstruction(
        line: line,
        description: "Remove redundant conformance to '\(protocolName)'",
        replacement: fixedLine,
        confidence: .exact
      )
    }

    return FixInstruction(
      line: line,
      description: "Remove redundant conformance to '\(protocolName)'",
      replacement: nil,
      confidence: .likely
    )
  }

  // MARK: - Pattern: Incorrect Argument Label

  /// `incorrect argument label in call (have 'x:', expected 'y:')`
  private func matchIncorrectLabel(_ msg: String, region: CodeRegion, line: Int) -> FixInstruction? {
    let pattern = #"incorrect argument label in call \(have '(\w+):', expected '(\w+):'\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let haveRange = Range(match.range(at: 1), in: msg),
          let expectedRange = Range(match.range(at: 2), in: msg) else { return nil }

    let have = String(msg[haveRange])
    let expected = String(msg[expectedRange])

    // Find the call site in the region and replace the label
    let regionLines = region.text.components(separatedBy: "\n")
    let targetLineIdx = line - 1 - region.startLine
    guard targetLineIdx >= 0, targetLineIdx < regionLines.count else {
      return FixInstruction(
        line: line,
        description: "Change argument label '\(have):' to '\(expected):'",
        replacement: nil,
        confidence: .likely
      )
    }

    let fixedLine = regionLines[targetLineIdx]
      .replacingOccurrences(of: "\(have):", with: "\(expected):")

    return FixInstruction(
      line: line,
      description: "Change argument label '\(have):' to '\(expected):'",
      replacement: fixedLine,
      confidence: .exact
    )
  }

  // MARK: - Pattern: Extra Argument

  /// `extra argument 'x' in call`
  private func matchExtraArgument(_ msg: String, region: CodeRegion, line: Int) -> FixInstruction? {
    let pattern = #"extra argument '(\w+)' in call"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let argRange = Range(match.range(at: 1), in: msg) else { return nil }

    let argName = String(msg[argRange])

    // Try to remove the extra argument from the call site
    let regionLines = region.text.components(separatedBy: "\n")
    let targetLineIdx = line - 1 - region.startLine
    guard targetLineIdx >= 0, targetLineIdx < regionLines.count else {
      return FixInstruction(
        line: line,
        description: "Remove extra argument '\(argName)' from call",
        replacement: nil,
        confidence: .likely
      )
    }

    var fixedLine = regionLines[targetLineIdx]
    // Remove patterns like: argName: value, or , argName: value
    let removePatterns = [
      #",\s*\#(argName):\s*[^,)]*"#,
      #"\#(argName):\s*[^,)]*,\s*"#
    ]
    for removePattern in removePatterns {
      if let range = fixedLine.range(of: removePattern, options: .regularExpression) {
        fixedLine.removeSubrange(range)
        return FixInstruction(
          line: line,
          description: "Remove extra argument '\(argName)' from call",
          replacement: fixedLine,
          confidence: .exact
        )
      }
    }

    return FixInstruction(
      line: line,
      description: "Remove extra argument '\(argName)' from call",
      replacement: nil,
      confidence: .likely
    )
  }

  // MARK: - Pattern: No Member

  /// `value of type 'X' has no member 'Y'`
  private func matchNoMember(
    _ msg: String,
    region: CodeRegion,
    line: Int,
    snapshot: ProjectSnapshot,
    apiHint: String?
  ) -> FixInstruction? {
    let pattern = #"value of type '(\w+)' has no member '(\w+)'"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let typeRange = Range(match.range(at: 1), in: msg),
          let memberRange = Range(match.range(at: 2), in: msg) else { return nil }

    let typeName = String(msg[typeRange])
    let memberName = String(msg[memberRange])

    // Look up actual members from snapshot
    let allTypes = snapshot.models + snapshot.services + snapshot.views
    if let typeInfo = allTypes.first(where: { $0.name == typeName }) {
      let availableMembers = (typeInfo.properties + typeInfo.methods).joined(separator: ", ")
      var desc = "'\(typeName)' has no member '\(memberName)'. Available: \(availableMembers)"
      if let hint = apiHint { desc += "\n\(hint)" }
      return FixInstruction(
        line: line,
        description: desc,
        replacement: nil,
        confidence: .likely
      )
    }

    // Fall back to API hint if available
    if let hint = apiHint {
      return FixInstruction(
        line: line,
        description: "'\(typeName)' has no member '\(memberName)'. \(hint)",
        replacement: nil,
        confidence: .likely
      )
    }

    return FixInstruction(
      line: line,
      description: "'\(typeName)' has no member '\(memberName)'",
      replacement: nil,
      confidence: .hint
    )
  }

  // MARK: - Pattern: Type Mismatch

  /// `cannot convert value of type 'X' to expected argument type 'Y'`
  private func matchTypeMismatch(_ msg: String, line: Int, apiHint: String?) -> FixInstruction? {
    let pattern = #"cannot convert value of type '([^']+)' to expected argument type '([^']+)'"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let fromRange = Range(match.range(at: 1), in: msg),
          let toRange = Range(match.range(at: 2), in: msg) else { return nil }

    let fromType = String(msg[fromRange])
    let toType = String(msg[toRange])

    var desc = "Cannot convert '\(fromType)' to '\(toType)'"
    if let hint = apiHint { desc += ". \(hint)" }

    return FixInstruction(
      line: line,
      description: desc,
      replacement: nil,
      confidence: .likely
    )
  }

  // MARK: - Pattern: Missing Argument

  /// `missing argument for parameter 'x' in call`
  private func matchMissingArgument(_ msg: String, line: Int, apiHint: String?) -> FixInstruction? {
    let pattern = #"missing argument for parameter '(\w+)' in call"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let paramRange = Range(match.range(at: 1), in: msg) else { return nil }

    let paramName = String(msg[paramRange])

    var desc = "Missing argument '\(paramName)'"
    if let hint = apiHint { desc += ". Correct signature: \(hint)" }

    return FixInstruction(
      line: line,
      description: desc,
      replacement: nil,
      confidence: .likely
    )
  }

  // MARK: - Pattern: Use of Unresolved Identifier

  /// `use of unresolved identifier 'x'`
  private func matchUseOfUnresolved(_ msg: String, line: Int) -> FixInstruction? {
    let pattern = #"use of unresolved identifier '(\w+)'"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
          let identRange = Range(match.range(at: 1), in: msg) else { return nil }

    let identifier = String(msg[identRange])

    return FixInstruction(
      line: line,
      description: "Unresolved identifier '\(identifier)' — check property declarations or imports",
      replacement: nil,
      confidence: .hint
    )
  }
}
