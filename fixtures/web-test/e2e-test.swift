#!/usr/bin/env swift
// e2e-test.swift — Manual E2E test harness for WebDriver
//
// Starts a local HTTP server, launches Chrome headless via WebDriver,
// runs assertions against the calculator test page.
//
// Usage: swift fixtures/web-test/e2e-test.swift
//
// Requires: Chrome installed, chromedriver matching Chrome version
//           (download from https://googlechromelabs.github.io/chrome-for-testing/)

import Foundation

let port = 8765
let driverPort = 4470

// MARK: - HTTP Server (serves the test page)

func startServer() -> Process {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
  process.arguments = ["-m", "http.server", "\(port)", "--directory", "fixtures/web-test"]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try! process.run()
  return process
}

// MARK: - ChromeDriver

func startChromeDriver() -> Process? {
  // Try local chromedriver first, then fall back to npx
  let process = Process()

  // Check for local chromedriver
  let localPath = "/tmp/chromedriver-mac-arm64/chromedriver"
  if FileManager.default.fileExists(atPath: localPath) {
    process.executableURL = URL(fileURLWithPath: localPath)
    process.arguments = ["--port=\(driverPort)"]
  } else {
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["npx", "--yes", "chromedriver", "--port=\(driverPort)"]
  }

  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  do {
    try process.run()
    return process
  } catch {
    print("❌ Could not start chromedriver: \(error)")
    return nil
  }
}

// MARK: - WebDriver HTTP Helpers

func webdriver(_ method: String, _ path: String, body: [String: Any]? = nil) -> [String: Any]? {
  let url = URL(string: "http://localhost:\(driverPort)\(path)")!
  var request = URLRequest(url: url, timeoutInterval: 10)
  request.httpMethod = method
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }

  let sem = DispatchSemaphore(value: 0)
  var result: [String: Any]?
  URLSession.shared.dataTask(with: request) { data, _, _ in
    if let data { result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
    sem.signal()
  }.resume()
  sem.wait()
  return result
}

func executeJS(_ sessionId: String, _ script: String) -> Any? {
  let resp = webdriver("POST", "/session/\(sessionId)/execute/sync",
    body: ["script": script, "args": []])
  return resp?["value"]
}

// MARK: - Test Runner

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String) {
  if condition {
    passed += 1
    print("  ✓ \(message)")
  } else {
    failed += 1
    print("  ✗ \(message)")
  }
}

// MARK: - Main

print("Starting HTTP server on port \(port)...")
let server = startServer()
sleep(1)

print("Starting ChromeDriver on port \(driverPort)...")
guard let driver = startChromeDriver() else {
  server.terminate()
  exit(1)
}
sleep(2)

print("Creating Chrome session (headless)...")
let sessionResp = webdriver("POST", "/session", body: [
  "capabilities": ["alwaysMatch": [
    "browserName": "chrome",
    "goog:chromeOptions": ["args": ["--headless=new", "--no-sandbox"]],
  ]],
])
guard let sessionId = (sessionResp?["value"] as? [String: Any])?["sessionId"] as? String else {
  print("❌ Failed to create session")
  print("   Response: \(sessionResp ?? [:])")
  driver.terminate(); server.terminate()
  exit(1)
}
print("Session: \(sessionId.prefix(12))...\n")

// Navigate
_ = webdriver("POST", "/session/\(sessionId)/url", body: ["url": "http://localhost:\(port)/index.html"])
sleep(1)

print("Running E2E tests...\n")

// Test 1: Page loads
let title = (webdriver("GET", "/session/\(sessionId)/title")?["value"] as? String) ?? ""
assert(title == "Junco E2E Test Page", "Page title is correct: '\(title)'")

// Test 2: H1 content
let h1 = executeJS(sessionId, "return document.getElementById('title').textContent") as? String ?? ""
assert(h1 == "Calculator", "H1 shows 'Calculator': '\(h1)'")

// Test 3: Form exists
let formExists = executeJS(sessionId, "return document.getElementById('calc-form') !== null") as? Bool ?? false
assert(formExists, "Calculator form exists")

// Test 4: Default values
let numA = executeJS(sessionId, "return document.getElementById('num-a').value") as? String ?? ""
assert(numA == "10", "Default value A is 10: '\(numA)'")

// Test 5: Calculate button click
_ = executeJS(sessionId, "document.getElementById('calculate').click()")
sleep(1)

// Test 6: Result displayed
let result = executeJS(sessionId, "return document.getElementById('result').textContent") as? String ?? ""
assert(result.contains("15"), "10 + 5 = 15: '\(result)'")

// Test 7: Result has success class
let resultClass = executeJS(sessionId, "return document.getElementById('result').className") as? String ?? ""
assert(resultClass.contains("pass"), "Result has 'pass' class: '\(resultClass)'")

// Test 8: Change operator and recalculate
_ = executeJS(sessionId, """
  document.getElementById('operator').value = '*';
  document.getElementById('calculate').click();
""")
sleep(1)
let multResult = executeJS(sessionId, "return document.getElementById('result').textContent") as? String ?? ""
assert(multResult.contains("50"), "10 * 5 = 50: '\(multResult)'")

// Test 9: Division by zero
_ = executeJS(sessionId, """
  document.getElementById('operator').value = '/';
  document.getElementById('num-b').value = '0';
  document.getElementById('calculate').click();
""")
sleep(1)
let divZero = executeJS(sessionId, "return document.getElementById('result').textContent") as? String ?? ""
assert(divZero.contains("division by zero"), "Division by zero handled: '\(divZero)'")

// Test 10: History accumulates
let historyCount = executeJS(sessionId, "return document.getElementById('history').children.length") as? Int ?? 0
assert(historyCount >= 3, "History has \(historyCount) entries (expected >= 3)")

// Cleanup
_ = webdriver("DELETE", "/session/\(sessionId)")
driver.terminate()
server.terminate()

print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
