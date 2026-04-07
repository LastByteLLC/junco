// UpdateChecker.swift — Background check for new junco releases on GitHub
//
// Queries the GitHub Releases API at most once per 24 hours, caches the result,
// and prints a one-line notice if a newer version is available.

import Foundation

/// Information about an available update.
public struct UpdateInfo: Codable, Sendable {
  public let version: String
  public let downloadURL: URL
  public let sha256: String?
  public let releaseNotes: String?
  public let publishedAt: String?
}

/// Cached result of an update check.
struct CachedCheck: Codable {
  let checkedAt: Date
  let info: UpdateInfo
}

/// Checks GitHub Releases for newer versions of junco.
public actor UpdateChecker {

  /// How often to poll GitHub (24 hours).
  private static let checkInterval: TimeInterval = 86_400

  /// Cache file for the last check result.
  private static var cacheURL: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base
      .appendingPathComponent("com.junco", isDirectory: true)
      .appendingPathComponent("update_check.json")
  }

  /// GitHub API endpoint for the latest release.
  private static var releaseURL: URL {
    let owner = JuncoVersion.repoOwner
    let repo = JuncoVersion.repoName
    return URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
  }

  public init() {}

  // MARK: - Background check (call from launch)

  /// Fire-and-forget background check. Prints a notice if an update is available.
  public func checkInBackground(currentVersion: String, isPipe: Bool) {
    guard !isPipe else { return }
    Task.detached(priority: .utility) { [self] in
      guard let info = await self.check(current: currentVersion) else { return }
      let msg = "  Update available: junco v\(info.version)"
        + " (you have v\(currentVersion)). Run `junco update` to upgrade."
      FileHandle.standardError.write(Data("\u{1B}[2m\(msg)\u{1B}[0m\n".utf8))
    }
  }

  // MARK: - Explicit check (for `junco update`)

  /// Check GitHub for a newer version. Returns nil if already up-to-date or on error.
  public func check(current: String) async -> UpdateInfo? {
    // Read cache — skip network if checked recently
    if let cached = readCache(),
      cached.checkedAt.timeIntervalSinceNow > -Self.checkInterval {
      return isNewer(cached.info.version, than: current) ? cached.info : nil
    }

    // Fetch latest release from GitHub API
    var request = URLRequest(url: Self.releaseURL)
    request.setValue(JuncoVersion.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10

    guard
      let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tagName = json["tag_name"] as? String
    else { return nil }

    let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

    // Skip LoRA-only releases (e.g. v0.5.0-lora)
    guard !tagName.contains("-lora") else { return nil }

    // Find the arm64 binary asset
    guard
      let assets = json["assets"] as? [[String: Any]],
      let binary = assets.first(where: { ($0["name"] as? String) == "junco-arm64" }),
      let urlString = binary["browser_download_url"] as? String,
      let downloadURL = URL(string: urlString)
    else { return nil }

    // Fetch SHA-256 from checksums.txt asset
    let sha256 = await fetchChecksum(from: assets, for: "junco-arm64")

    let info = UpdateInfo(
      version: version,
      downloadURL: downloadURL,
      sha256: sha256,
      releaseNotes: json["body"] as? String,
      publishedAt: json["published_at"] as? String
    )

    // Cache the result
    writeCache(CachedCheck(checkedAt: Date(), info: info))

    return isNewer(version, than: current) ? info : nil
  }

  /// Force a fresh check, ignoring the cache.
  public func forceCheck(current: String) async -> UpdateInfo? {
    clearCache()
    return await check(current: current)
  }

  // MARK: - Checksum fetch

  private func fetchChecksum(from assets: [[String: Any]], for filename: String) async -> String? {
    guard
      let checksumAsset = assets.first(where: { ($0["name"] as? String) == "checksums.txt" }),
      let urlString = checksumAsset["browser_download_url"] as? String,
      let url = URL(string: urlString)
    else { return nil }

    var request = URLRequest(url: url)
    request.setValue(JuncoVersion.userAgent, forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    guard
      let (data, _) = try? await URLSession.shared.data(for: request),
      let text = String(data: data, encoding: .utf8)
    else { return nil }

    // Format: "<sha256>  <filename>"
    for line in text.components(separatedBy: .newlines) {
      let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
      if parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces) == filename {
        return String(parts[0])
      }
    }
    return nil
  }

  // MARK: - Semver comparison

  private func isNewer(_ remote: String, than local: String) -> Bool {
    let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
    let localParts = local.split(separator: ".").compactMap { Int($0) }
    let count = max(remoteParts.count, localParts.count)
    for i in 0..<count {
      let remote = i < remoteParts.count ? remoteParts[i] : 0
      let local = i < localParts.count ? localParts[i] : 0
      if remote > local { return true }
      if remote < local { return false }
    }
    return false
  }

  // MARK: - Cache persistence

  private func readCache() -> CachedCheck? {
    guard let data = try? Data(contentsOf: Self.cacheURL) else { return nil }
    return try? JSONDecoder().decode(CachedCheck.self, from: data)
  }

  private func writeCache(_ check: CachedCheck) {
    let dir = Self.cacheURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(check) {
      try? data.write(to: Self.cacheURL, options: .atomic)
    }
  }

  private func clearCache() {
    try? FileManager.default.removeItem(at: Self.cacheURL)
  }
}
