// AdapterDownloader.swift — Downloads LoRA adapter from GitHub Releases
//
// Shows a progress bar in the terminal. Caches locally so it only
// downloads once per OS version.

import CommonCrypto
import Foundation

/// Downloads and caches LoRA adapters from the manifest.
public struct AdapterDownloader: Sendable {

  public init() {}

  /// Result of an adapter resolution attempt.
  public enum ResolveResult: Sendable {
    /// Adapter is cached and ready to load
    case cached(URL)
    /// Adapter was downloaded and is ready to load
    case downloaded(URL)
    /// No adapter available for this OS version
    case noRelease
    /// User declined the download
    case declined
    /// Download failed
    case failed(String)
    /// Offline mode — skip download
    case offline
  }

  /// Resolve the adapter for the current OS. Downloads if needed.
  /// - Parameters:
  ///   - offline: If true, only use cached adapter (no network)
  ///   - askPermission: Closure that asks user yes/no. Returns true if user approves.
  ///   - isPipe: If true, skip interactive prompts (auto-decline download)
  public func resolve(
    offline: Bool = false,
    askPermission: (() -> Bool)? = nil,
    isPipe: Bool = false
  ) async -> ResolveResult {
    guard let release = AdapterManifest.releaseForCurrentOS() else {
      return .noRelease
    }

    let adapterPath = AdapterManifest.cachedAdapterPath(for: release)

    // Already cached — use it
    if AdapterManifest.isCached(release) {
      return .cached(adapterPath)
    }

    // Offline mode — can't download
    if offline {
      return .offline
    }

    // Pipe mode — no interactive prompt
    if isPipe {
      return .declined
    }

    // Ask user permission
    if let ask = askPermission {
      guard ask() else { return .declined }
    }

    // Download
    do {
      try await download(release: release, to: adapterPath)
      return .downloaded(adapterPath)
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  // MARK: - Download with Progress

  private func download(release: AdapterRelease, to destination: URL) async throws {
    let fm = FileManager.default

    // Create the .fmadapter directory
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)

    // Download weights (large file — show progress)
    let weightsPath = destination.appendingPathComponent("adapter_weights.bin")
    try await downloadFile(
      from: release.weightsURL,
      to: weightsPath,
      label: "Downloading LoRA adapter",
      expectedSHA256: release.weightsSHA256
    )

    // Download metadata (tiny — no progress needed)
    let metadataPath = destination.appendingPathComponent("metadata.json")
    try await downloadFile(
      from: release.metadataURL,
      to: metadataPath,
      label: nil,
      expectedSHA256: release.metadataSHA256
    )
  }

  private func downloadFile(from url: URL, to destination: URL, label: String?, expectedSHA256: String? = nil) async throws {
    let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: label.map { ProgressDelegate(label: $0) })

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw DownloadError.httpError(code)
    }

    // Verify SHA-256 integrity if expected hash is provided
    if let expected = expectedSHA256 {
      let data = try Data(contentsOf: tempURL)
      let actual = sha256(data)
      guard actual == expected else {
        throw DownloadError.integrityCheckFailed(expected: expected, actual: actual)
      }
    }

    // Move to final location
    let fm = FileManager.default
    if fm.fileExists(atPath: destination.path) {
      try fm.removeItem(at: destination)
    }
    try fm.moveItem(at: tempURL, to: destination)

    if label != nil {
      print("\r\u{1B}[K", terminator: "")
      fflush(stdout)
    }
  }

  /// Compute SHA-256 hex string for data.
  private func sha256(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  enum DownloadError: LocalizedError {
    case httpError(Int)
    case integrityCheckFailed(expected: String, actual: String)

    var errorDescription: String? {
      switch self {
      case .httpError(let code):
        return "Download failed with HTTP \(code)"
      case .integrityCheckFailed(let expected, let actual):
        return "Integrity check failed: expected SHA-256 \(expected.prefix(12))..., got \(actual.prefix(12))..."
      }
    }
  }
}

// MARK: - Progress Delegate

/// URLSession delegate that prints a progress bar to the terminal.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let label: String
  private var lastPrintedPercent = -1

  init(label: String) {
    self.label = label
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }

    let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
    guard percent != lastPrintedPercent else { return }
    lastPrintedPercent = percent

    let mbWritten = Double(totalBytesWritten) / 1_048_576
    let mbTotal = Double(totalBytesExpectedToWrite) / 1_048_576
    let barWidth = 30
    let filled = Int(Double(barWidth) * Double(percent) / 100)
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)

    print("\r\(label) [\(bar)] \(percent)% (\(String(format: "%.1f", mbWritten))/\(String(format: "%.1f", mbTotal)) MB)", terminator: "")
    fflush(stdout)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // handled in the calling code
  }
}
