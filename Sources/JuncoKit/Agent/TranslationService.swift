// TranslationService.swift — Auto-detect and translate non-English input
//
// Uses Apple's Translation framework for on-device translation.
// Detects input language via NLLanguageRecognizer, translates to English
// before the agent processes it, preserving the original for display.

import Foundation
import NaturalLanguage
import Translation

/// Handles auto-translation of non-English input to English.
public struct TranslationService: Sendable {
  // LanguageAvailability is not Sendable but stateless — safe for reads.
  private nonisolated(unsafe) static let availability = LanguageAvailability()

  public init() {}

  /// Process input: detect language, translate if non-English.
  /// Returns (processedText, originalLanguage) — processedText is English.
  public func process(_ input: String) async -> (text: String, sourceLanguage: String?) {
    let detector = LanguageDetector()
    guard let lang = detector.detect(input), lang != "en", lang != "und" else {
      return (input, nil)
    }

    // Check if translation is available
    let source = Locale.Language(identifier: lang)
    let target = Locale.Language(identifier: "en")

    let status = await Self.availability.status(from: source, to: target)
    guard status == .installed || status == .supported else {
      return (input, lang)  // Can't translate, pass through
    }

    // Translate
    do {
      let session = TranslationSession(installedSource: source, target: target)
      let translated = try await session.translate(input)
      return (translated.targetText, lang)
    } catch {
      return (input, lang)  // Translation failed, pass through
    }
  }
}
