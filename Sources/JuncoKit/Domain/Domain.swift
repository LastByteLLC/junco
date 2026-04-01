// Domain.swift — Project domain detection and configuration
//
// Auto-detects Swift/Apple projects from marker files (Package.swift,
// *.xcodeproj, *.xcworkspace). Falls back to general for non-Swift projects.

import Foundation

/// Supported project domains.
public enum DomainKind: String, Codable, Sendable, CaseIterable {
  case swift
  case general
}

/// Domain-specific configuration that guides the agent's behavior.
public struct DomainConfig: Sendable {
  public let kind: DomainKind
  public let displayName: String
  public let fileExtensions: [String]
  public let buildCommand: String?
  public let testCommand: String?
  public let lintCommand: String?
  public let promptHint: String  // Injected into system prompts

  /// Marker files that identify this domain.
  public let markers: [String]
}

/// Pre-defined domain configurations.
public enum Domains {
  public static let swift = DomainConfig(
    kind: .swift,
    displayName: "Swift / Apple",
    fileExtensions: ["swift"],
    buildCommand: "swift build 2>&1 | tail -20",
    testCommand: "swift test 2>&1 | tail -30",
    lintCommand: "swiftlint lint --quiet 2>&1 | head -20",
    promptHint: "This is a Swift project using SPM. Use Swift conventions: structs over classes, async/await, actors for shared state.",
    markers: ["Package.swift", "*.xcodeproj", "*.xcworkspace"]
  )

  public static let general = DomainConfig(
    kind: .general,
    displayName: "General",
    fileExtensions: Config.generalExtensions,
    buildCommand: nil,
    testCommand: nil,
    lintCommand: nil,
    promptHint: "General-purpose project. Identify the language from file extensions and follow its conventions.",
    markers: []
  )

  public static func forKind(_ kind: DomainKind) -> DomainConfig {
    switch kind {
    case .swift: return swift
    case .general: return general
    }
  }
}

/// Detects the project domain from the working directory.
public struct DomainDetector: Sendable {
  public let workingDirectory: String

  public init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
  }

  /// Detect the project domain, checking for manual override first.
  public func detect() -> DomainConfig {
    // 1. Check for manual override in .junco/config.json
    if let manual = loadManualConfig() {
      return Domains.forKind(manual)
    }

    // 2. Auto-detect from marker files
    let fm = FileManager.default

    // Swift markers
    if fm.fileExists(atPath: path("Package.swift")) {
      return Domains.swift
    }
    // Check for Xcode projects
    if let contents = try? fm.contentsOfDirectory(atPath: workingDirectory) {
      if contents.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
        return Domains.swift
      }
    }

    return Domains.general
  }

  private func loadManualConfig() -> DomainKind? {
    let configPath = path(".junco/config.json")
    guard let data = FileManager.default.contents(atPath: configPath),
          let json = try? JSONDecoder().decode(JuncoConfig.self, from: data)
    else { return nil }
    return json.domain
  }

  private func path(_ relative: String) -> String {
    (workingDirectory as NSString).appendingPathComponent(relative)
  }
}

/// Manual project configuration stored in .junco/config.json.
public struct JuncoConfig: Codable, Sendable {
  public var domain: DomainKind?
  public var notifications: NotificationConfig?

  public init(domain: DomainKind? = nil, notifications: NotificationConfig? = nil) {
    self.domain = domain
    self.notifications = notifications
  }

  /// Load config from a project directory. Returns defaults if not found.
  public static func load(from workingDirectory: String) -> JuncoConfig {
    let path = (workingDirectory as NSString)
      .appendingPathComponent("\(Config.projectDirName)/config.json")
    guard let data = FileManager.default.contents(atPath: path),
          let config = try? JSONDecoder().decode(JuncoConfig.self, from: data)
    else { return JuncoConfig() }
    return config
  }
}

/// Notification settings within .junco/config.json.
public struct NotificationConfig: Codable, Sendable {
  public var enabled: Bool?
  public var thresholdSeconds: Int?
  public var method: String?  // "system", "bell", "none"
}
