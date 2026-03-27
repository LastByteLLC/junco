#!/usr/bin/env swift
// train_classifier.swift — Train and evaluate intent classifiers
//
// Trains multiple algorithm types, evaluates each, picks the best.
// Outputs a .mlmodel to Training/IntentClassifier.mlmodel
//
// Run: swift Training/train_classifier.swift

import CreateML
import Foundation

print("Loading training data...")
let dataURL = URL(fileURLWithPath: "Training/intent_data.json")
let fullData = try MLDataTable(contentsOf: dataURL)

print("Total examples: \(fullData.rows.count)")
print("Label distribution: (see stats.txt)")

// Split: 80% train, 20% test
let (trainData, testData) = fullData.randomSplit(by: 0.8, seed: 42)
print("\nTrain: \(trainData.rows.count), Test: \(testData.rows.count)")

// MARK: - Train multiple algorithms

struct ModelResult {
  let name: String
  let accuracy: Double
  let model: MLTextClassifier
}

var results: [ModelResult] = []

// Algorithm 1: Maximum Entropy (default, fast)
print("\n--- Training: Maximum Entropy ---")
let maxEntParams = MLTextClassifier.ModelParameters(algorithm: .maxEnt(revision: nil))
let maxEntModel = try MLTextClassifier(
  trainingData: trainData,
  textColumn: "text",
  labelColumn: "label",
  parameters: maxEntParams
)
let maxEntEval = maxEntModel.evaluation(on: testData, textColumn: "text", labelColumn: "label")
let maxEntAcc = (1.0 - maxEntEval.classificationError) * 100
print("  Accuracy: \(String(format: "%.1f", maxEntAcc))%")
results.append(ModelResult(name: "MaxEnt", accuracy: maxEntAcc, model: maxEntModel))

// Algorithm 2: Conditional Random Fields
print("\n--- Training: CRF ---")
let crfParams = MLTextClassifier.ModelParameters(algorithm: .crf(revision: nil))
let crfModel = try MLTextClassifier(
  trainingData: trainData,
  textColumn: "text",
  labelColumn: "label",
  parameters: crfParams
)
let crfEval = crfModel.evaluation(on: testData, textColumn: "text", labelColumn: "label")
let crfAcc = (1.0 - crfEval.classificationError) * 100
print("  Accuracy: \(String(format: "%.1f", crfAcc))%")
results.append(ModelResult(name: "CRF", accuracy: crfAcc, model: crfModel))

// Algorithm 3: Transfer Learning (BERT-based, slower but better for nuance)
print("\n--- Training: Transfer Learning (BERT) ---")
let tlParams = MLTextClassifier.ModelParameters(algorithm: .transferLearning(.elmoEmbedding, revision: nil))
let tlModel = try MLTextClassifier(
  trainingData: trainData,
  textColumn: "text",
  labelColumn: "label",
  parameters: tlParams
)
let tlEval = tlModel.evaluation(on: testData, textColumn: "text", labelColumn: "label")
let tlAcc = (1.0 - tlEval.classificationError) * 100
print("  Accuracy: \(String(format: "%.1f", tlAcc))%")
results.append(ModelResult(name: "TransferLearning", accuracy: tlAcc, model: tlModel))

// MARK: - Select best and save

print("\n=== Results ===")
for r in results.sorted(by: { $0.accuracy > $1.accuracy }) {
  let marker = r.accuracy == results.max(by: { $0.accuracy < $1.accuracy })?.accuracy ? "***" : "   "
  print("\(marker) \(r.name): \(String(format: "%.1f", r.accuracy))%")
}

let best = results.max(by: { $0.accuracy < $1.accuracy })!
print("\nBest: \(best.name) at \(String(format: "%.1f", best.accuracy))%")

// Save the best model
let outputURL = URL(fileURLWithPath: "Training/IntentClassifier.mlmodel")
try best.model.write(to: outputURL)
print("Saved to: Training/IntentClassifier.mlmodel")

// Also save a metadata file
let metadata = """
{
  "algorithm": "\(best.name)",
  "accuracy": \(String(format: "%.1f", best.accuracy)),
  "trainingExamples": \(trainData.rows.count),
  "testExamples": \(testData.rows.count),
  "labels": ["fix", "add", "refactor", "explain", "test", "explore"],
  "trainedAt": "\(ISO8601DateFormatter().string(from: Date()))"
}
"""
try metadata.write(toFile: "Training/model_metadata.json", atomically: true, encoding: .utf8)
print("Metadata saved.")

// MARK: - Test with specific adversarial examples

print("\n=== Adversarial Tests ===")
let adversarial = [
  ("fix the login bug", "fix"),
  ("FIX THE LOGIN BUG", "fix"),
  ("arregla el error en main.swift", "fix"),
  ("explain handleClick", "explain"),
  ("[Paste #1: 45 lines, 1200 chars] fix this", "fix"),
  ("fixx the bugg", "fix"),
  ("make it better", "refactor"),
  ("add tests", "test"),
  ("where is login defined", "explore"),
  ("修复错误", "fix"),
  ("tests", "test"),
  ("grep", "explore"),
]

var correct = 0
for (text, expected) in adversarial {
  let prediction = try best.model.prediction(from: text)
  let match = prediction == expected ? "✓" : "✗"
  if prediction == expected { correct += 1 }
  print("  \(match) \"\(text)\" → \(prediction) (expected: \(expected))")
}
print("Adversarial: \(correct)/\(adversarial.count)")
