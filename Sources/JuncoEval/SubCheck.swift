// SubCheck.swift — Declarative sub-checks for hard eval fixtures.
//
// Each fixture declares a list of SubCheck entries; the evaluator runs each
// independently against the generated file and reports per-check pass/fail.
// With ~5 sub-checks per fixture × 10 fixtures × 5 replicates = 250 Bernoulli
// sub-trials per run, std err drops to ~3 pp (vs ~8 pp at the case-pass-rate
// level), enabling detection of ~6 pp candidate deltas.

import Foundation

/// One assertion about the generated file. Discriminated by `kind`.
/// Optional fields carry the payload for whichever kind this check is.
public struct SubCheck: Sendable, Codable {
  public let kind: String
  public let name: String?
  public let category: String?
  public let conformsTo: [String]?
  public let on: String?
  public let names: [String]?
  public let member: String?
  public let returns: String?
  public let minSimilarity: Double?
  public let reference: String?
  public let absent: Bool?

  public init(
    kind: String, name: String? = nil, category: String? = nil,
    conformsTo: [String]? = nil, on: String? = nil, names: [String]? = nil,
    member: String? = nil, returns: String? = nil,
    minSimilarity: Double? = nil, reference: String? = nil, absent: Bool? = nil
  ) {
    self.kind = kind; self.name = name; self.category = category
    self.conformsTo = conformsTo; self.on = on; self.names = names
    self.member = member; self.returns = returns
    self.minSimilarity = minSimilarity; self.reference = reference
    self.absent = absent
  }

  /// Short human-readable description for traces and summary reports.
  public var label: String {
    switch kind {
    case "compiles": return "compiles"
    case "hasType": return "hasType(\(name ?? "?"))"
    case "hasCase": return "hasCase(\(on ?? "?").\(names?.joined(separator: ",") ?? "?"))"
    case "hasConformance": return "hasConformance(\(on ?? "?"):\(conformsTo?.joined(separator: ",") ?? "?"))"
    case "hasMember": return "hasMember(\(on ?? "?").\(name ?? "?"))"
    case "doesNotReferenceType": return "doesNotReferenceType(\(name ?? "?"))"
    default: return kind
    }
  }
}

/// Result of running one SubCheck.
public struct SubCheckResult: Sendable, Codable {
  public let label: String
  public let passed: Bool
  /// Short diagnostic string on failure (e.g. "enum TodoStatus has 2/3 cases: missing done").
  public let detail: String?

  public init(label: String, passed: Bool, detail: String? = nil) {
    self.label = label; self.passed = passed; self.detail = detail
  }
}
