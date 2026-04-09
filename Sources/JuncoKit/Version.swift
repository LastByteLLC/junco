// Version.swift — Single source of truth for the junco version string

/// The current junco version. Update this constant when cutting a release.
public enum JuncoVersion {
  public static let current = "0.6.3"

  /// GitHub repository used for releases and update checks.
  public static let repoOwner = "LastByteLLC"
  public static let repoName = "junco"

  /// User-Agent header sent with all HTTP requests.
  public static var userAgent: String { "junco/\(current) (on-device coding agent)" }
}
