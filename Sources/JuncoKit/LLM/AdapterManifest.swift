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
      weightsURL: URL(string: "https://github.com/LastByteLLC/junco/releases/download/v0.6.0-lora/adapter_weights.bin")!,
      metadataURL: URL(string: "https://github.com/LastByteLLC/junco/releases/download/v0.6.0-lora/metadata.json")!,
      weightsSHA256: "1dcb38e64663bda23469fee04a2dbcd5929ce0f8f155c020f0ae28e6e231bdb4",
      metadataSHA256: "702ca8900af57b5f96d92975fbdc3510ac8a4a8606e6a0d657d569b3bc6df1ea",
      description: "Junco v4: 11,126 samples, epoch 2, val_loss 0.370"
    )
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
