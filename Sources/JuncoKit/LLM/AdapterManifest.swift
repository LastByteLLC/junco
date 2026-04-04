// AdapterManifest.swift — Declares which LoRA adapter to use for each OS version
//
// Embedded in the binary at compile time. Maps OS version → adapter download URLs.
// The adapter is downloaded on first run and cached locally.

import Foundation

/// A single adapter release targeting a specific base model version.
public struct AdapterRelease: Sendable {
  /// macOS/iOS version this adapter targets (e.g., "26" for macOS 26.x)
  public let osVersion: String
  /// Base model signature this adapter was trained against
  public let baseModelSignature: String
  /// URL to adapter_weights.bin
  public let weightsURL: URL
  /// URL to metadata.json
  public let metadataURL: URL
  /// Expected SHA-256 of adapter_weights.bin
  public let weightsSHA256: String?
  /// Expected SHA-256 of metadata.json
  public let metadataSHA256: String?
  /// Human-readable description
  public let description: String
}

/// Compiled-in manifest of all available adapter releases.
/// Update this when training new adapters for new OS versions.
public enum AdapterManifest {

  /// All known adapter releases, newest first.
  public static let releases: [AdapterRelease] = [
    AdapterRelease(
      osVersion: "26",
      baseModelSignature: "9799725ff8e851184037110b422d891ad3b92ec1",
      weightsURL: URL(string: "https://github.com/LastByteLLC/junco/releases/download/v0.5.0-lora/adapter_weights.bin")!,
      metadataURL: URL(string: "https://github.com/LastByteLLC/junco/releases/download/v0.5.0-lora/metadata.json")!,
      weightsSHA256: "81296e0a3ca3e2fd78715c71c58d4d9258609a13374d68eaff5c6afe4944300c",
      metadataSHA256: "7a313fea980e7cd5fd77bfe60d5bce81b3eb1ec7aaf786295c85b1489c859cc7",
      description: "Junco v3: 10,247 samples, epoch 2, val_loss 0.395"
    ),
  ]

  /// Find the adapter release matching the current OS version.
  public static func releaseForCurrentOS() -> AdapterRelease? {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let majorStr = "\(version.majorVersion)"
    return releases.first { $0.osVersion == majorStr }
  }

  /// Local cache directory for downloaded adapters.
  public static var cacheDirectory: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("com.junco.adapters", isDirectory: true)
  }

  /// Path to the cached .fmadapter package for a given release.
  public static func cachedAdapterPath(for release: AdapterRelease) -> URL {
    cacheDirectory
      .appendingPathComponent("junco_\(release.osVersion)", isDirectory: true)
      .appendingPathExtension("fmadapter")
  }

  /// Whether the adapter for a release is already cached locally.
  public static func isCached(_ release: AdapterRelease) -> Bool {
    let path = cachedAdapterPath(for: release)
    let weightsPath = path.appendingPathComponent("adapter_weights.bin")
    let metadataPath = path.appendingPathComponent("metadata.json")
    return FileManager.default.fileExists(atPath: weightsPath.path)
      && FileManager.default.fileExists(atPath: metadataPath.path)
  }
}
