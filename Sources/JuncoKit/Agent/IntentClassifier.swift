// IntentClassifier.swift — ML-based intent classification
//
// Uses a Core ML text classifier (CRF, trained on 9.5K examples)
// to classify task type in ~10ms instead of ~2s LLM call.
// Falls back to LLM if the model isn't available.

import CoreML
import Foundation
import NaturalLanguage

/// Fast intent classification using a trained Core ML model.
/// NLModel is not Sendable but is safe for our use: loaded once at init, read-only after.
public struct IntentClassifier: @unchecked Sendable {
  private let mlModel: NLModel?

  public init() {
    // Try to load the compiled model from common locations
    let searchPaths = [
      // Adjacent to the binary
      Bundle.main.bundleURL.appendingPathComponent("IntentClassifier.mlmodelc"),
      // In the Training directory (development)
      URL(fileURLWithPath: "Training/IntentClassifier.mlmodelc"),
      // In ~/.junco/models/
      URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".junco/models/IntentClassifier.mlmodelc"),
    ]

    var loaded: NLModel?
    for path in searchPaths {
      if FileManager.default.fileExists(atPath: path.path) {
        if let compiled = try? MLModel(contentsOf: path),
           let model = try? NLModel(mlModel: compiled) {
          loaded = model
          break
        }
      }
    }

    self.mlModel = loaded
  }

  /// Whether the ML model is available.
  public var isAvailable: Bool { mlModel != nil }

  /// Classify task type from a query. Returns nil if model unavailable.
  public func classifyTaskType(_ query: String) -> String? {
    guard let model = mlModel else { return nil }
    return model.predictedLabel(for: query)
  }

  /// Classify with confidence. Returns (label, confidence) or nil.
  public func classifyWithConfidence(_ query: String) -> (label: String, confidence: Double)? {
    guard let model = mlModel else { return nil }
    guard let label = model.predictedLabel(for: query) else { return nil }
    let hypotheses = model.predictedLabelHypotheses(for: query, maximumCount: 1)
    let confidence = hypotheses[label] ?? 0.0
    return (label, confidence)
  }
}

/// Uses NLLanguageRecognizer to detect input language.
public struct LanguageDetector: Sendable {
  public init() {}

  /// Detect the dominant language of the input text.
  /// Returns ISO 639-1 code (e.g., "en", "es", "zh") or nil.
  public func detect(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else { return nil }
    return language.rawValue
  }

  /// Check if the input is likely English.
  public func isEnglish(_ text: String) -> Bool {
    let lang = detect(text)
    return lang == nil || lang == "en"
  }
}
