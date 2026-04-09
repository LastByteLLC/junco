// AFMTokenEstimator.swift — Calibrated token count estimation for Apple Foundation Models
//
// Approximates AFM's SentencePiece BPE tokenizer using character-class heuristics
//
// Design: conservative (slight overestimate) to prevent context overflow.
// Target accuracy: within ±10% of real token count for Swift code and prompts.
//
// Key SentencePiece BPE behavior:
//   - Text is preprocessed: prepend ▁, replace all spaces with ▁
//   - Single inter-word space merges into the next word's ▁ prefix (costs 0 extra tokens)
//   - Indentation (2+ spaces at line start) is a separate token
//   - Newlines are always 1 token each
//   - Common words (up to ~12 chars) are single tokens in the 150K vocab
//   - Punctuation creates token boundaries; common pairs ((), {}, ->) merge

import Foundation

/// Estimates token counts for Apple Foundation Models.
/// Uses calibrated character-class heuristics that approximate SentencePiece BPE behavior.
public struct AFMTokenEstimator: Sendable {

  /// Estimate token count for the given text.
  /// Conservative: tends to slightly overestimate to prevent context overflow.
  public static func countTokens(_ text: String) -> Int {
    guard !text.isEmpty else { return 0 }

    var tokens = 0
    let scalars = Array(text.unicodeScalars)
    var i = 0
    var atLineStart = true

    while i < scalars.count {
      let ch = scalars[i]

      if ch == "\n" || ch == "\r" {
        tokens += 1
        i += 1
        if ch == "\r" && i < scalars.count && scalars[i] == "\n" { i += 1 }
        atLineStart = true
      } else if ch == " " || ch == "\t" {
        // Consume the full whitespace run
        let wsStart = i
        i += 1
        while i < scalars.count && (scalars[i] == " " || scalars[i] == "\t") { i += 1 }
        let wsLen = i - wsStart

        if atLineStart {
          // Indentation: 1 token per ~16 spaces (BPE merges ▁ runs up to ~16)
          tokens += max(1, (wsLen + 12) / 16)
        } else if wsLen > 1 {
          // Multiple spaces mid-line: 1 token for the extra ▁ run
          tokens += 1
        }
        // Single space between words: FREE (merges into next word's ▁ prefix)
      } else {
        // Non-whitespace word: collect until next whitespace
        let wordStart = i
        while i < scalars.count && !isWhitespace(scalars[i]) { i += 1 }
        tokens += estimateWord(scalars, from: wordStart, to: i)
        atLineStart = false
      }
    }

    return max(1, tokens)
  }

  // MARK: - Word Estimation

  /// Estimate tokens for a single non-whitespace word.
  private static func estimateWord(
    _ scalars: [Unicode.Scalar], from start: Int, to end: Int
  ) -> Int {
    let len = end - start
    guard len > 0 else { return 0 }

    // Classify characters
    var alphaCount = 0
    var digitCount = 0
    var punctCount = 0
    for j in start..<end {
      let s = scalars[j]
      if isAlpha(s) {
        alphaCount += 1
      } else if isDigit(s) {
        digitCount += 1
      } else {
        punctCount += 1
      }
    }

    // Single character: always 1 token
    if len == 1 { return 1 }

    // Two characters: common pairs merge ((), {}, ->, ==, etc.)
    if len == 2 { return (punctCount == 2 || alphaCount == 2) ? 1 : 2 }

    // Pure alphabetic word (keywords, identifiers)
    if punctCount == 0 && digitCount == 0 {
      return estimateAlphaTokens(alphaCount)
    }

    // Digit-heavy (numbers, hex literals, version strings)
    if digitCount > len / 2 {
      return max(1, (digitCount + 1) / 2 + max(0, punctCount - 1))
    }

    // Mixed: split at punctuation boundaries, estimate segments
    return estimateMixedWord(scalars, from: start, to: end)
  }

  /// Estimate tokens for a pure alphabetic word.
  /// Calibrated against AFM's 150K BPE vocab:
  ///   - 1-12 chars: usually 1 token (covers most English words and Swift keywords)
  ///   - 13-20 chars: 2 tokens (CamelCase identifiers split at subword boundaries)
  ///   - 20+ chars: ~1 token per 7 chars
  private static func estimateAlphaTokens(_ length: Int) -> Int {
    switch length {
    case 0: return 0
    case 1...12: return 1
    case 13...20: return 2
    default: return (length + 5) / 7
    }
  }

  /// Estimate tokens for a word with mixed alpha, digits, and punctuation.
  /// Each punctuation character is ~1 token (only a few specific pairs merge in BPE,
  /// and those are already handled by the len==2 path for standalone pairs).
  private static func estimateMixedWord(
    _ scalars: [Unicode.Scalar], from start: Int, to end: Int
  ) -> Int {
    var tokens = 0
    var segStart = start

    for j in start..<end {
      if isPunct(scalars[j]) {
        let segLen = j - segStart
        if segLen > 0 {
          tokens += estimateAlphaTokens(segLen)
        }
        tokens += 1  // Each punctuation char = 1 token
        segStart = j + 1
      }
    }

    let tailLen = end - segStart
    if tailLen > 0 {
      tokens += estimateAlphaTokens(tailLen)
    }

    return max(1, tokens)
  }

  // MARK: - Character Classification

  private static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
    s == " " || s == "\t" || s == "\n" || s == "\r"
  }

  private static func isAlpha(_ s: Unicode.Scalar) -> Bool {
    (s.value >= 0x41 && s.value <= 0x5A) ||  // A-Z
    (s.value >= 0x61 && s.value <= 0x7A) ||  // a-z
    s.value == 0x5F                           // _
  }

  private static func isDigit(_ s: Unicode.Scalar) -> Bool {
    s.value >= 0x30 && s.value <= 0x39
  }

  private static func isPunct(_ s: Unicode.Scalar) -> Bool {
    let v = s.value
    if v >= 0x21 && v <= 0x2F { return true }  // !"#$%&'()*+,-./
    if v >= 0x3A && v <= 0x40 { return true }  // :;<=>?@
    if v >= 0x5B && v <= 0x5E { return true }  // [\]^
    if v == 0x60 { return true }               // `
    if v >= 0x7B && v <= 0x7E { return true }  // {|}~
    return false
  }
}
