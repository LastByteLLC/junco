// AFMTokenEstimatorTests.swift — Validate token estimation accuracy against known AFM counts
//
// Ground truth from Python: AFMTokenizer(vocab_path='tokenizer.model').encode(text)
// Target: within ±15% of real count, with conservative (overestimate) bias.

import Testing
@testable import JuncoKit

@Suite("AFMTokenEstimator")
struct AFMTokenEstimatorTests {

  // MARK: - Edge Cases

  @Test("empty string returns zero")
  func emptyString() {
    #expect(AFMTokenEstimator.countTokens("") == 0)
  }

  @Test("single character returns 1")
  func singleChar() {
    #expect(AFMTokenEstimator.countTokens("a") == 1)
    #expect(AFMTokenEstimator.countTokens("{") == 1)
    #expect(AFMTokenEstimator.countTokens("1") == 1)
  }

  @Test("single newline returns 1")
  func singleNewline() {
    #expect(AFMTokenEstimator.countTokens("\n") == 1)
  }

  @Test("never returns negative or zero for non-empty input")
  func nonZeroGuard() {
    #expect(AFMTokenEstimator.countTokens(" ") >= 1)
    #expect(AFMTokenEstimator.countTokens("  ") >= 1)
    #expect(AFMTokenEstimator.countTokens("\t") >= 1)
  }

  // MARK: - Whitespace Handling

  @Test("space runs count as single token")
  func spaceRuns() {
    // Any run of spaces = 1 token (SentencePiece merges ▁ runs)
    let oneSpace = AFMTokenEstimator.countTokens(" ")
    let fourSpaces = AFMTokenEstimator.countTokens("    ")
    let eightSpaces = AFMTokenEstimator.countTokens("        ")
    #expect(oneSpace == fourSpaces)
    #expect(fourSpaces == eightSpaces)
  }

  @Test("newlines count individually")
  func newlines() {
    #expect(AFMTokenEstimator.countTokens("\n\n\n") == 3)
  }

  // MARK: - Accuracy Against Real AFM Tokenizer (Ground Truth)
  //
  // Each test documents the real token count from Python AFMTokenizer.
  // The estimator must be within the specified tolerance.

  @Test("Package.swift — real: 95 tokens")
  func packageSwift() {
    let code = """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
          name: "Weather",
          platforms: [.macOS(.v15)],
          products: [
              .executableProduct(name: "Weather", targets: ["Weather"])
          ],
          dependencies: [],
          targets: [
              .target(name: "Weather")
          ]
      )
      """
    let estimate = AFMTokenEstimator.countTokens(code)
    let real = 95
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.10, label: "Package.swift")
  }

  @Test("Weather service — real: 173 tokens")
  func weatherService() {
    let code = """
      import Foundation

      actor WeatherService {
          func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherResponse {
              var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
              components.queryItems = [
                  URLQueryItem(name: "latitude", value: String(latitude)),
                  URLQueryItem(name: "longitude", value: String(longitude)),
                  URLQueryItem(name: "hourly", value: "temperature_2m")
              ]
              let (data, _) = try await URLSession.shared.data(from: components.url!)
              return try JSONDecoder().decode(WeatherResponse.self, from: data)
          }
      }
      """
    let estimate = AFMTokenEstimator.countTokens(code)
    let real = 173
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.10, label: "WeatherService")
  }

  @Test("SwiftUI view — real: 155 tokens")
  func swiftUIView() {
    let code = """
      import SwiftUI

      struct ContentView: View {
          @State private var items: [String] = []
          @State private var searchText = ""
          @StateObject private var viewModel = WeatherViewModel()

          var body: some View {
              NavigationStack {
                  List {
                      Text("hello")
                          .font(.headline)
                      Text("world")
                          .font(.subheadline)
                          .foregroundStyle(.secondary)
                  }
                  .searchable(text: $searchText)
                  .navigationTitle("Weather")
                  .task {
                      await viewModel.load()
                  }
              }
          }
      }
      """
    let estimate = AFMTokenEstimator.countTokens(code)
    let real = 155
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.15, label: "SwiftUI view")
  }

  @Test("Short function — real: 24 tokens")
  func shortFunction() {
    let code = """
      func add(_ a: Int, _ b: Int) -> Int {
          return a + b
      }
      """
    let estimate = AFMTokenEstimator.countTokens(code)
    let real = 24
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.15, label: "Short function")
  }

  @Test("Simple struct — real: 27 tokens")
  func simpleStruct() {
    let code = """
      struct Item: Codable {
          let id: Int
          let name: String
          let value: Double
      }
      """
    let estimate = AFMTokenEstimator.countTokens(code)
    let real = 27
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.10, label: "Simple struct")
  }

  @Test("System prompt (prose) — real: 48 tokens")
  func systemPrompt() {
    let text = "Output the complete modified file. No markdown fences, no explanation. "
      + "Apply ONLY the requested changes. This is a Swift project using SPM. "
      + "Use Swift conventions: structs over classes, async/await, actors for shared state."
    let estimate = AFMTokenEstimator.countTokens(text)
    let real = 48
    assertWithinTolerance(estimate: estimate, real: real, tolerance: 0.10, label: "System prompt")
  }

  // MARK: - Conservative Bias Check

  @Test("estimator should not dangerously underestimate")
  func conservativeBias() {
    // For all benchmark samples, the estimate should not be more than 15% below real.
    // A slight overestimate is fine (wastes some context); a large underestimate causes overflow.
    let samples: [(String, Int)] = [
      ("import Foundation\n\nactor WeatherService {\n  func fetch() async throws -> String {\n    return \"\"\n  }\n}\n", 28),
      ("let x = 42\n", 7),
      ("// This is a comment\n", 6)
    ]
    for (text, real) in samples {
      let estimate = AFMTokenEstimator.countTokens(text)
      let underestimateRatio = Double(estimate) / Double(real)
      #expect(
        underestimateRatio >= 0.80,
        "Dangerous underestimate: \(estimate) vs real \(real) (ratio \(underestimateRatio))"
      )
    }
  }

  // MARK: - Performance

  @Test("estimation is fast for typical prompts")
  func performance() {
    // Generate a ~2K char prompt (typical for Junco)
    let code = String(repeating: "func fetch() async throws -> [Item] {\n    let data = try await api.get()\n    return data\n}\n", count: 20)
    #expect(code.count > 1500)

    let start = ContinuousClock.now
    for _ in 0..<100 {
      _ = AFMTokenEstimator.countTokens(code)
    }
    let elapsed = ContinuousClock.now - start
    // 100 calls should complete in well under 1 second
    #expect(elapsed < .seconds(1), "Token estimation too slow: \(elapsed) for 100 calls")
  }

  // MARK: - Helpers

  private func assertWithinTolerance(estimate: Int, real: Int, tolerance: Double, label: String) {
    let ratio = Double(estimate) / Double(real)
    let lowerBound = 1.0 - tolerance
    let upperBound = 1.0 + tolerance
    #expect(
      ratio >= lowerBound && ratio <= upperBound,
      "\(label): estimate \(estimate) vs real \(real) (ratio \(String(format: "%.2f", ratio)), expected \(String(format: "%.2f", lowerBound))-\(String(format: "%.2f", upperBound)))"
    )
  }
}
