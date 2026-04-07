// SelfUpdater.swift — Downloads and installs a new junco binary in place
//
// Downloads to a temp file, verifies SHA-256, then atomically swaps
// the running binary. macOS allows renaming a running executable.

import CommonCrypto
import Foundation

public enum UpdateError: LocalizedError {
  case checksumMismatch(expected: String, actual: String)
  case downloadFailed(String)
  case permissionDenied(String)
  case binaryNotFound

  public var errorDescription: String? {
    switch self {
    case .checksumMismatch(let expected, let actual):
      return "Checksum mismatch: expected \(expected.prefix(16))..., got \(actual.prefix(16))..."
    case .downloadFailed(let reason):
      return "Download failed: \(reason)"
    case .permissionDenied(let path):
      return "Permission denied writing to \(path). Try: sudo junco update"
    case .binaryNotFound:
      return "Could not determine the path to the running binary."
    }
  }
}

public struct SelfUpdater: Sendable {

  public init() {}

  /// Update the current binary to the version described in `info`.
  public func update(to info: UpdateInfo) async throws {
    let executablePath = try resolveExecutablePath()

    // Check we can write to the binary location
    let dir = (executablePath as NSString).deletingLastPathComponent
    guard FileManager.default.isWritableFile(atPath: dir) else {
      throw UpdateError.permissionDenied(executablePath)
    }

    let tempPath = executablePath + ".download"
    let backupPath = executablePath + ".backup"

    // 1. Download to temp file with progress
    print("Downloading junco v\(info.version)...")
    try await downloadWithProgress(from: info.downloadURL, to: tempPath)

    // 2. Verify SHA-256
    if let expected = info.sha256 {
      let actual = try sha256OfFile(atPath: tempPath)
      guard actual == expected else {
        try? FileManager.default.removeItem(atPath: tempPath)
        throw UpdateError.checksumMismatch(expected: expected, actual: actual)
      }
      print("Checksum verified.")
    }

    // 3. Set executable permission
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: tempPath)

    // 4. Atomic swap: backup current -> move new into place
    let fm = FileManager.default
    if fm.fileExists(atPath: backupPath) {
      try fm.removeItem(atPath: backupPath)
    }
    try fm.moveItem(atPath: executablePath, toPath: backupPath)

    do {
      try fm.moveItem(atPath: tempPath, toPath: executablePath)
    } catch {
      // Rollback: restore backup if the move failed
      try? fm.moveItem(atPath: backupPath, toPath: executablePath)
      throw error
    }

    // 5. Clean up backup
    try? fm.removeItem(atPath: backupPath)

    print("Updated to junco v\(info.version). Restart to use the new version.")
  }

  // MARK: - Resolve binary path

  private func resolveExecutablePath() throws -> String {
    // ProcessInfo gives us the original argv[0], resolve symlinks
    let argv0 = ProcessInfo.processInfo.arguments[0]
    let fm = FileManager.default

    // Resolve to absolute path
    let absolute: String
    if argv0.hasPrefix("/") {
      absolute = argv0
    } else {
      absolute = fm.currentDirectoryPath + "/" + argv0
    }

    // Resolve symlinks
    let resolved = (try? fm.destinationOfSymbolicLink(atPath: absolute)) ?? absolute

    guard fm.fileExists(atPath: resolved) else {
      throw UpdateError.binaryNotFound
    }

    return resolved
  }

  // MARK: - Download with progress

  private func downloadWithProgress(from url: URL, to destinationPath: String) async throws {
    var request = URLRequest(url: url)
    request.setValue(JuncoVersion.userAgent, forHTTPHeaderField: "User-Agent")

    let (bytes, response) = try await URLSession.shared.bytes(for: request)

    guard
      let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw UpdateError.downloadFailed("HTTP \(code)")
    }

    let expectedLength = httpResponse.expectedContentLength
    try await streamToFile(
      bytes: bytes, destinationPath: destinationPath,
      expectedLength: expectedLength
    )
  }

  private func streamToFile(
    bytes: URLSession.AsyncBytes, destinationPath: String,
    expectedLength: Int64
  ) async throws {
    let showProgress = expectedLength > 0
    FileManager.default.createFile(atPath: destinationPath, contents: nil)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: destinationPath))
    defer { try? handle.close() }

    var totalWritten: Int64 = 0
    var lastPercent = -1
    var buffer = Data()

    for try await byte in bytes {
      buffer.append(byte)
      if buffer.count >= 64 * 1024 {
        handle.write(buffer)
        totalWritten += Int64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
        if showProgress {
          lastPercent = printProgress(
            totalWritten, of: expectedLength, lastPercent: lastPercent
          )
        }
      }
    }

    if !buffer.isEmpty { handle.write(buffer) }
    try handle.close()
    if showProgress { print("\r\u{1B}[K", terminator: ""); fflush(stdout) }
  }

  private func printProgress(_ written: Int64, of total: Int64, lastPercent: Int) -> Int {
    let percent = Int(Double(written) / Double(total) * 100)
    guard percent != lastPercent else { return lastPercent }
    let barWidth = 30
    let filled = Int(Double(barWidth) * Double(percent) / 100)
    let fill = String(repeating: "█", count: filled)
    let empty = String(repeating: "░", count: barWidth - filled)
    let mb = String(format: "%.1f", Double(written) / 1_048_576)
    let tot = String(format: "%.1f", Double(total) / 1_048_576)
    print("\rDownloading [\(fill)\(empty)] \(percent)% (\(mb)/\(tot) MB)", terminator: "")
    fflush(stdout)
    return percent
  }

  // MARK: - SHA-256

  private func sha256OfFile(atPath path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
