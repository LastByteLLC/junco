// TemplateRenderer.swift — Intent-based file generation for structured formats
//
// Instead of asking the 3B model to generate raw XML/DSL, the model fills
// in simple @Generable intents (booleans, strings) and this renderer
// produces syntactically-perfect output using proper APIs (XMLDocument/PropertyListSerialization).

import Foundation
import FoundationModels

// MARK: - Entitlements

@Generable
public struct EntitlementsIntent: Codable, Sendable {
  @Guide(description: "Enable app sandbox") public var sandbox: Bool
  @Guide(description: "Allow outbound network connections") public var networkClient: Bool
  @Guide(description: "Allow inbound network connections") public var networkServer: Bool
  @Guide(description: "Allow user-selected file read-write access") public var userFileAccess: Bool
  @Guide(description: "Allow camera access") public var camera: Bool
  @Guide(description: "Allow microphone access") public var microphone: Bool
  @Guide(description: "Allow USB device access") public var usb: Bool
  @Guide(description: "Allow Bluetooth access") public var bluetooth: Bool
  @Guide(description: "Allow location access") public var location: Bool
  @Guide(description: "App group identifiers, empty if none") public var appGroups: [String]
}

// MARK: - Package.swift

@Generable
public struct PackageIntent: Codable, Sendable {
  @Guide(description: "Package name") public var name: String
  @Guide(description: "Product type: library or executable") public var productType: String
  @Guide(description: "Target names") public var targets: [String]
  @Guide(description: "Test target names") public var testTargets: [String]
  @Guide(description: "Dependency URLs like https://github.com/apple/swift-argument-parser") public var dependencies: [String]
  @Guide(description: "Minimum macOS version number like 15") public var macOS: String
  @Guide(description: "Minimum iOS version number like 18") public var iOS: String
}

// MARK: - Info.plist

@Generable
public struct PlistIntent: Codable, Sendable {
  @Guide(description: "App display name") public var displayName: String
  @Guide(description: "Bundle identifier like com.example.myapp") public var bundleIdentifier: String
  @Guide(description: "Camera usage description, empty if not needed") public var cameraUsage: String
  @Guide(description: "Microphone usage description, empty if not needed") public var microphoneUsage: String
  @Guide(description: "Location usage description, empty if not needed") public var locationUsage: String
  @Guide(description: "Photo library usage description, empty if not needed") public var photoUsage: String
  @Guide(description: "Additional Info.plist keys as key=value pairs") public var additionalKeys: [String]
}

// MARK: - Privacy Manifest (.xcprivacy)

@Generable
public struct PrivacyManifestIntent: Codable, Sendable {
  @Guide(description: "Accessed API types like NSPrivacyAccessedAPICategoryFileTimestamp") public var accessedAPITypes: [String]
  @Guide(description: "Reasons for each API type like C617.1") public var accessedAPIReasons: [String]
  @Guide(description: "Whether the app collects tracking data") public var tracking: Bool
  @Guide(description: "Collected data types like NSPrivacyCollectedDataTypeName") public var collectedDataTypes: [String]
}

// MARK: - Gitignore

@Generable
public struct GitignoreIntent: Codable, Sendable {
  @Guide(description: "Include Swift package patterns (.build, .swiftpm)") public var swiftPackage: Bool
  @Guide(description: "Include Xcode patterns (DerivedData, xcuserdata)") public var xcode: Bool
  @Guide(description: "Include CocoaPods patterns (Pods/)") public var cocoapods: Bool
  @Guide(description: "Include macOS system files (.DS_Store)") public var macOS: Bool
  @Guide(description: "Additional custom patterns to ignore, one per entry") public var custom: [String]
}

// MARK: - Xcconfig

@Generable
public struct XcconfigIntent: Codable, Sendable {
  @Guide(description: "Configuration name like Debug or Release") public var name: String
  @Guide(description: "Build settings as KEY = VALUE pairs") public var settings: [String]
}

// MARK: - SwiftUI App Entry Point

@Generable
public struct AppEntryPointIntent: Codable, Sendable {
  @Guide(description: "App struct name like PodcastApp") public var appName: String
  @Guide(description: "Root view type name like ContentView or PodcastListView") public var rootView: String
  @Guide(description: "State properties like @State private var viewModel = PodcastViewModel(), empty if none") public var stateProperties: [String]
}

// MARK: - Swift Test File

@Generable
public struct SwiftTestIntent: Codable, Sendable {
  @Guide(description: "Name of the module being tested") public var moduleName: String
  @Guide(description: "Names of types to test") public var typeNames: [String]
  @Guide(description: "Test function names without the test prefix") public var testNames: [String]
  @Guide(description: "Brief description of what each test checks") public var testDescriptions: [String]
}

// MARK: - Model File

@Generable
public struct ModelTypeIntent: Codable, Sendable {
  @Guide(description: "Type name like Podcast or Episode") public var typeName: String
  @Guide(description: "Properties as type declarations like let id: Int or var name: String") public var properties: [String]
  @Guide(description: "Protocol conformances like Identifiable, Codable, Hashable") public var conformances: [String]
}

@Generable
public struct ModelsFileIntent: Codable, Sendable {
  @Guide(description: "All model types to create in this file") public var models: [ModelTypeIntent]
}

// MARK: - Service File

@Generable
public struct ServiceMethodIntent: Codable, Sendable {
  @Guide(description: "Method signature like func fetchTopPodcasts() async throws -> [Podcast]") public var signature: String
  @Guide(description: "The URL string this method fetches from, empty if not a network method") public var url: String
  @Guide(description: "The return type to decode like [Podcast] or User") public var decodedType: String
}

@Generable
public struct ServiceIntent: Codable, Sendable {
  @Guide(description: "Actor name like PodcastService or UserService") public var actorName: String
  @Guide(description: "Methods this service provides") public var methods: [ServiceMethodIntent]
}

// MARK: - ViewModel File

@Generable
public struct ViewModelMethodIntent: Codable, Sendable {
  @Guide(description: "Method name like loadTopPodcasts or loadEpisodes") public var name: String
  @Guide(description: "Parameters like podcastID: Int, empty if none") public var parameters: String
  @Guide(description: "The service method to call like service.fetchTopPodcasts()") public var serviceCall: String
  @Guide(description: "The state property to assign the result to like podcasts") public var targetProperty: String
}

@Generable
public struct ViewModelIntent: Codable, Sendable {
  @Guide(description: "Class name like PodcastViewModel") public var className: String
  @Guide(description: "State properties like var podcasts: [Podcast] = []") public var stateProperties: [String]
  @Guide(description: "Private properties like private let service = PodcastService()") public var privateProperties: [String]
  @Guide(description: "Async loading methods") public var methods: [ViewModelMethodIntent]
}

// MARK: - Code Fragment (for targeted retry)

@Generable
public struct CodeFragment: Codable, Sendable {
  @Guide(description: "The corrected code") public var content: String
}

// MARK: - Renderer

public struct TemplateRenderer: Sendable {

  public init() {}

  /// Detect if a file path should use template-based generation.
  public func shouldUseTemplate(filePath: String) -> Bool {
    templateSystemPrompt(for: filePath) != nil
  }

  /// Returns the system prompt for template-based generation, or nil if not a template file.
  /// Used by `resolveTemplate` to determine intent and render.
  public func templateSystemPrompt(for filePath: String) -> String? {
    let name = (filePath as NSString).lastPathComponent.lowercased()
    if name.hasSuffix(".entitlements") {
      return "Determine which entitlements this app needs based on the user's request."
    } else if name.hasSuffix("package.swift") {
      return "Determine the SPM package configuration: name, targets, dependencies, platforms."
    } else if name == "info.plist" || name.hasSuffix(".plist") {
      return "Determine the Info.plist configuration: display name, bundle ID, privacy permissions needed."
    } else if name.hasSuffix(".xcprivacy") {
      return "Determine the privacy manifest: accessed API types, reasons, tracking, collected data."
    } else if name == ".gitignore" {
      return "Determine which patterns to ignore. For Swift projects, include swiftPackage and xcode. Always include macOS."
    } else if name.hasSuffix(".xcconfig") {
      return "Generate xcconfig build settings as KEY = VALUE pairs."
    } else if name.hasSuffix("app.swift") {
      return "Determine the app name and root view for this SwiftUI app entry point."
    } else if name.contains("model") && name.hasSuffix(".swift") {
      return "Extract the model types, their properties (with types), and protocol conformances from the request."
    } else if name.contains("service") && name.hasSuffix(".swift") {
      return "Extract the service actor name and its methods with signatures, URLs, and return types."
    } else if name.contains("viewmodel") && name.hasSuffix(".swift") {
      return "Extract the ViewModel class name, state properties, private dependencies, and async loading methods."
    }
    return nil
  }

  /// Generate template content by dispatching to the appropriate intent type and renderer.
  /// Returns nil if the file path doesn't match any template.
  public func resolveTemplate(
    filePath: String,
    prompt: String,
    adapter: any LLMAdapter
  ) async throws -> String? {
    let name = (filePath as NSString).lastPathComponent.lowercased()
    guard let system = templateSystemPrompt(for: filePath) else { return nil }

    if name.hasSuffix(".entitlements") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: EntitlementsIntent.self, options: nil)
      return renderEntitlements(intent)
    } else if name.hasSuffix("package.swift") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: PackageIntent.self, options: nil)
      return renderPackage(intent)
    } else if name == "info.plist" || name.hasSuffix(".plist") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: PlistIntent.self, options: nil)
      return renderPlist(intent)
    } else if name.hasSuffix(".xcprivacy") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: PrivacyManifestIntent.self, options: nil)
      return renderPrivacyManifest(intent)
    } else if name == ".gitignore" {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: GitignoreIntent.self, options: nil)
      return renderGitignore(intent)
    } else if name.hasSuffix(".xcconfig") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: XcconfigIntent.self, options: nil)
      return renderXcconfig(intent)
    } else if name.hasSuffix("app.swift") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: AppEntryPointIntent.self, options: nil)
      return renderAppEntryPoint(intent)
    } else if name.contains("model") && name.hasSuffix(".swift") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: ModelsFileIntent.self, options: nil)
      return renderModels(intent)
    } else if name.contains("service") && name.hasSuffix(".swift") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: ServiceIntent.self, options: nil)
      return renderService(intent)
    } else if name.contains("viewmodel") && name.hasSuffix(".swift") {
      let intent = try await adapter.generateStructured(prompt: prompt, system: system, as: ViewModelIntent.self, options: nil)
      return renderViewModel(intent)
    }
    return nil
  }

  // MARK: - Entitlements

  public func renderEntitlements(_ intent: EntitlementsIntent) -> String {
    var dict: [String: Any] = [:]

    if intent.sandbox { dict["com.apple.security.app-sandbox"] = true }
    if intent.networkClient { dict["com.apple.security.network.client"] = true }
    if intent.networkServer { dict["com.apple.security.network.server"] = true }
    if intent.userFileAccess { dict["com.apple.security.files.user-selected.read-write"] = true }
    if intent.camera { dict["com.apple.security.device.camera"] = true }
    if intent.microphone { dict["com.apple.security.device.audio-input"] = true }
    if intent.usb { dict["com.apple.security.device.usb"] = true }
    if intent.bluetooth { dict["com.apple.security.device.bluetooth"] = true }
    if intent.location { dict["com.apple.security.personal-information.location"] = true }

    let groups = intent.appGroups.filter { !$0.isEmpty }
    if !groups.isEmpty {
      dict["com.apple.security.application-groups"] = groups
    }

    return serializePlist(dict)
  }

  // MARK: - Package.swift

  public func renderPackage(_ intent: PackageIntent) -> String {
    var platforms: [String] = []
    if !intent.macOS.isEmpty { platforms.append(".macOS(.v\(intent.macOS))") }
    if !intent.iOS.isEmpty { platforms.append(".iOS(.v\(intent.iOS))") }
    let platformsLine = platforms.isEmpty ? "" : "\n    platforms: [\(platforms.joined(separator: ", "))],"

    let mainTargets = intent.targets.isEmpty ? [intent.name] : intent.targets
    let productName = mainTargets.first ?? intent.name
    let productLine: String
    if intent.productType == "executable" {
      productLine = ".executableProduct(name: \"\(productName)\", targets: [\(mainTargets.map { "\"\($0)\"" }.joined(separator: ", "))])"
    } else {
      productLine = ".library(name: \"\(productName)\", targets: [\(mainTargets.map { "\"\($0)\"" }.joined(separator: ", "))])"
    }

    var deps: [String] = []
    for url in intent.dependencies where !url.isEmpty {
      deps.append("        .package(url: \"\(url)\", from: \"1.0.0\")")
    }
    let depsBlock = deps.isEmpty ? "" : "\n\(deps.joined(separator: ",\n"))\n    "

    var targets: [String] = []
    for t in mainTargets {
      targets.append("        .target(name: \"\(t)\")")
    }
    for t in intent.testTargets where !t.isEmpty {
      let dep = mainTargets.first ?? intent.name
      targets.append("        .testTarget(name: \"\(t)\", dependencies: [\"\(dep)\"])")
    }

    return """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: "\(intent.name)",\(platformsLine)
        products: [
            \(productLine)
        ],
        dependencies: [\(depsBlock)],
        targets: [
    \(targets.joined(separator: ",\n"))
        ]
    )
    """
  }

  // MARK: - Info.plist

  public func renderPlist(_ intent: PlistIntent) -> String {
    var dict: [String: Any] = [
      "CFBundleName": intent.displayName,
      "CFBundleIdentifier": intent.bundleIdentifier,
      "CFBundleVersion": "1",
      "CFBundleShortVersionString": "1.0",
      "CFBundlePackageType": "APPL",
    ]
    if !intent.cameraUsage.isEmpty {
      dict["NSCameraUsageDescription"] = intent.cameraUsage
    }
    if !intent.microphoneUsage.isEmpty {
      dict["NSMicrophoneUsageDescription"] = intent.microphoneUsage
    }
    if !intent.locationUsage.isEmpty {
      dict["NSLocationWhenInUseUsageDescription"] = intent.locationUsage
    }
    if !intent.photoUsage.isEmpty {
      dict["NSPhotoLibraryUsageDescription"] = intent.photoUsage
    }
    for kv in intent.additionalKeys where kv.contains("=") {
      let parts = kv.split(separator: "=", maxSplits: 1)
      if parts.count == 2 {
        dict[String(parts[0])] = String(parts[1])
      }
    }
    return serializePlist(dict)
  }

  // MARK: - Privacy Manifest

  public func renderPrivacyManifest(_ intent: PrivacyManifestIntent) -> String {
    var dict: [String: Any] = [
      "NSPrivacyTracking": intent.tracking,
    ]

    if !intent.accessedAPITypes.isEmpty {
      var apiEntries: [[String: Any]] = []
      for (i, apiType) in intent.accessedAPITypes.enumerated() {
        let reason = i < intent.accessedAPIReasons.count ? intent.accessedAPIReasons[i] : "C617.1"
        apiEntries.append([
          "NSPrivacyAccessedAPIType": apiType,
          "NSPrivacyAccessedAPITypeReasons": [reason],
        ])
      }
      dict["NSPrivacyAccessedAPITypes"] = apiEntries
    }

    if !intent.collectedDataTypes.isEmpty {
      dict["NSPrivacyCollectedDataTypes"] = intent.collectedDataTypes
    }

    return serializePlist(dict)
  }

  // MARK: - Gitignore

  public func renderGitignore(_ intent: GitignoreIntent) -> String {
    var lines: [String] = ["# Generated by junco"]
    if intent.swiftPackage {
      lines += ["", "# Swift Package Manager", ".build/", ".swiftpm/", "Package.resolved"]
    }
    if intent.xcode {
      lines += ["", "# Xcode", "DerivedData/", "xcuserdata/", "*.xcodeproj/xcuserdata/", "*.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist"]
    }
    if intent.cocoapods {
      lines += ["", "# CocoaPods", "Pods/", "Podfile.lock"]
    }
    if intent.macOS {
      lines += ["", "# macOS", ".DS_Store", "._*", "*.swp", "*~"]
    }
    for pattern in intent.custom where !pattern.isEmpty {
      lines.append(pattern)
    }
    return lines.joined(separator: "\n") + "\n"
  }

  // MARK: - Xcconfig

  public func renderXcconfig(_ intent: XcconfigIntent) -> String {
    var lines = ["// \(intent.name).xcconfig", "// Generated by junco", ""]
    for setting in intent.settings where !setting.isEmpty {
      lines.append(setting)
    }
    return lines.joined(separator: "\n") + "\n"
  }

  // MARK: - SwiftUI App Entry Point

  public func renderAppEntryPoint(_ intent: AppEntryPointIntent) -> String {
    let props = intent.stateProperties.filter { !$0.isEmpty }
    return SwiftCode {
      Import("SwiftUI")
      Blank()
      Struct(intent.appName, attributes: ["@main"], conformances: ["App"]) {
        for prop in props {
          Property(prop)
        }
        if !props.isEmpty { Blank() }
        ComputedVar("body", type: "some Scene") {
          Line("WindowGroup {")
          Line("    \(intent.rootView)()")
          Line("}")
        }
      }
    }.render()
  }

  // MARK: - Models File

  public func renderModels(_ intent: ModelsFileIntent) -> String {
    SwiftCode {
      Import("Foundation")
      for (_, model) in intent.models.enumerated() {
        Blank()
        Struct(model.typeName, conformances: model.conformances) {
          for prop in model.properties where !prop.isEmpty {
            Property(prop.hasPrefix("let ") || prop.hasPrefix("var ") ? prop : "let \(prop)")
          }
        }
      }
    }.render()
  }

  // MARK: - Service File

  public func renderService(_ intent: ServiceIntent) -> String {
    SwiftCode {
      Import("Foundation")
      Blank()
      Actor(intent.actorName) {
        for (i, method) in intent.methods.enumerated() {
          if i > 0 { Blank() }
          let sig = method.signature.hasPrefix("func ") ? method.signature : "func \(method.signature)"
          Function(sig) {
            if !method.url.isEmpty {
              Line("let url = URL(string: \"\(method.url)\")!")
              Line("let (data, _) = try await URLSession.shared.data(from: url)")
              if !method.decodedType.isEmpty {
                Line("return try JSONDecoder().decode(\(method.decodedType).self, from: data)")
              }
            } else {
              Comment("TODO: implement")
            }
          }
        }
      }
    }.render()
  }

  // MARK: - ViewModel File

  public func renderViewModel(_ intent: ViewModelIntent) -> String {
    SwiftCode {
      Import("Foundation")
      Import("Observation")
      Blank()
      Class(intent.className, attributes: ["@Observable"]) {
        for prop in intent.stateProperties where !prop.isEmpty {
          Property(prop.hasPrefix("var ") ? prop : "var \(prop)")
        }
        if !intent.stateProperties.isEmpty { Blank() }
        for prop in intent.privateProperties where !prop.isEmpty {
          Property(prop)
        }
        if !intent.privateProperties.isEmpty { Blank() }
        for (i, method) in intent.methods.enumerated() {
          if i > 0 { Blank() }
          let params = method.parameters.isEmpty ? "" : "\(method.parameters)"
          Function("func \(method.name)(\(params)) async") {
            Line("isLoading = true")
            Line("do {")
            Line("    \(method.targetProperty) = try await \(method.serviceCall)")
            Line("} catch {")
            Line("    print(\"\\(error)\")")
            Line("}")
            Line("isLoading = false")
          }
        }
      }
    }.render()
  }

  // MARK: - Swift Test File

  public func renderSwiftTest(_ intent: SwiftTestIntent) -> String {
    return SwiftCode {
      Import("Testing")
      Line("@testable import \(intent.moduleName)")
      Blank()
      for (i, testName) in intent.testNames.enumerated() {
        let desc = i < intent.testDescriptions.count ? intent.testDescriptions[i] : testName
        Function("@Test func \(testName)()") {
          Comment(desc)
        }
        Blank()
      }
    }.render()
  }

  // MARK: - Plist Serialization

  /// Serialize a dictionary to Apple plist XML format using PropertyListSerialization.
  private func serializePlist(_ dict: [String: Any]) -> String {
    guard let data = try? PropertyListSerialization.data(
      fromPropertyList: dict,
      format: .xml,
      options: 0
    ) else {
      // Fallback: shouldn't happen with valid dict, but return empty plist
      return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict/>\n</plist>"
    }
    return String(data: data, encoding: .utf8) ?? ""
  }
}
