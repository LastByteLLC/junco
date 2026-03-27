// WebDriverClient.swift — W3C WebDriver protocol client
//
// Communicates with browser WebDriver servers (safaridriver, chromedriver,
// geckodriver) over HTTP REST API. Supports:
// - Session management (create/delete)
// - Navigation
// - JavaScript execution
// - DOM queries via CSS selectors
// - Element interaction (click, type)
// - Screenshots
// - Page source
//
// The client manages driver subprocess lifecycle automatically.

import Foundation

/// Result of a WebDriver operation.
public struct WebDriverResult: Sendable {
  public let success: Bool
  public let value: String?
  public let error: String?
}

/// WebDriver client for browser automation.
public actor WebDriverClient {
  private let browser: DetectedBrowser
  private let port: Int
  private var driverProcess: Process?
  private var sessionId: String?

  public init(browser: DetectedBrowser, port: Int = 4449) {
    self.browser = browser
    self.port = port
  }

  // MARK: - Lifecycle

  /// Start the WebDriver and create a browser session.
  public func start(headless: Bool = true) async -> Bool {
    // Start the driver process
    guard await startDriver() else { return false }

    // Wait for driver to be ready
    try? await Task.sleep(for: .seconds(2))

    // Create session
    return await createSession(headless: headless)
  }

  /// Stop the browser session and driver.
  public func stop() async {
    if let sid = sessionId {
      _ = await request("DELETE", path: "/session/\(sid)")
      sessionId = nil
    }
    driverProcess?.terminate()
    driverProcess = nil
  }

  /// Whether a session is active.
  public var isActive: Bool { sessionId != nil }

  // MARK: - Navigation

  /// Navigate to a URL.
  public func navigate(to url: String) async -> WebDriverResult {
    guard let sid = sessionId else { return .init(success: false, value: nil, error: "No session") }
    let resp = await request("POST", path: "/session/\(sid)/url", body: ["url": url])
    return resp
  }

  /// Get the current page title.
  public func title() async -> String? {
    guard let sid = sessionId else { return nil }
    let resp = await request("GET", path: "/session/\(sid)/title")
    return resp.value
  }

  /// Get the current URL.
  public func currentURL() async -> String? {
    guard let sid = sessionId else { return nil }
    let resp = await request("GET", path: "/session/\(sid)/url")
    return resp.value
  }

  // MARK: - JavaScript Execution

  /// Execute synchronous JavaScript and return the result.
  public func executeJS(_ script: String, args: [Any] = []) async -> WebDriverResult {
    guard let sid = sessionId else { return .init(success: false, value: nil, error: "No session") }
    let body: [String: Any] = ["script": script, "args": args]
    return await request("POST", path: "/session/\(sid)/execute/sync", body: body)
  }

  /// Execute async JavaScript (with callback).
  public func executeAsyncJS(_ script: String, args: [Any] = []) async -> WebDriverResult {
    guard let sid = sessionId else { return .init(success: false, value: nil, error: "No session") }
    let body: [String: Any] = ["script": script, "args": args]
    return await request("POST", path: "/session/\(sid)/execute/async", body: body)
  }

  // MARK: - DOM Queries

  /// Get inner text of elements matching a CSS selector.
  public func queryText(selector: String) async -> String? {
    let resp = await executeJS(
      "return Array.from(document.querySelectorAll(arguments[0])).map(e=>e.textContent).join('\\n')",
      args: [selector]
    )
    return resp.value
  }

  /// Get the count of elements matching a selector.
  public func queryCount(selector: String) async -> Int? {
    let resp = await executeJS(
      "return document.querySelectorAll(arguments[0]).length",
      args: [selector]
    )
    return resp.value.flatMap { Int($0) }
  }

  /// Get an attribute of the first matching element.
  public func queryAttribute(selector: String, attribute: String) async -> String? {
    let resp = await executeJS(
      "var e = document.querySelector(arguments[0]); return e ? e.getAttribute(arguments[1]) : null",
      args: [selector, attribute]
    )
    return resp.value
  }

  // MARK: - Element Interaction

  /// Click the first element matching a selector.
  public func click(selector: String) async -> WebDriverResult {
    await executeJS("document.querySelector(arguments[0])?.click()", args: [selector])
  }

  /// Type text into an input matching a selector.
  public func type(selector: String, text: String) async -> WebDriverResult {
    await executeJS(
      "var e = document.querySelector(arguments[0]); if(e){e.value=arguments[1]; e.dispatchEvent(new Event('input',{bubbles:true}))}",
      args: [selector, text]
    )
  }

  // MARK: - Page Content

  /// Get the full page source HTML.
  public func pageSource() async -> String? {
    guard let sid = sessionId else { return nil }
    let resp = await request("GET", path: "/session/\(sid)/source")
    return resp.value
  }

  /// Take a screenshot, returns base64-encoded PNG.
  public func screenshot() async -> String? {
    guard let sid = sessionId else { return nil }
    let resp = await request("GET", path: "/session/\(sid)/screenshot")
    return resp.value
  }

  // MARK: - Driver Management

  private func startDriver() async -> Bool {
    let process = Process()

    switch browser.name {
    case "Safari":
      process.executableURL = URL(fileURLWithPath: "/usr/bin/safaridriver")
      process.arguments = ["-p", "\(port)"]

    case "Google Chrome":
      // Try local chromedriver, then npx
      if let driverPath = browser.driverPath {
        process.executableURL = URL(fileURLWithPath: driverPath)
      } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npx", "--yes", "chromedriver", "--port=\(port)"]
      }
      if process.arguments == nil {
        process.arguments = ["--port=\(port)"]
      }

    case _ where browser.name.contains("Firefox"):
      if let driverPath = browser.driverPath {
        process.executableURL = URL(fileURLWithPath: driverPath)
      } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npx", "--yes", "geckodriver", "--port", "\(port)"]
      }
      if process.arguments == nil || process.arguments?.contains("--port") == false {
        process.arguments = (process.arguments ?? []) + ["--port", "\(port)"]
      }

    default:
      return false
    }

    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      driverProcess = process
      return true
    } catch {
      return false
    }
  }

  private func createSession(headless: Bool) async -> Bool {
    var capabilities: [String: Any] = [:]

    switch browser.name {
    case "Safari":
      capabilities["browserName"] = "safari"

    case "Google Chrome":
      capabilities["browserName"] = "chrome"
      var chromeOpts: [String: Any] = [:]
      var args = ["--no-sandbox", "--disable-gpu"]
      if headless { args.append("--headless=new") }
      chromeOpts["args"] = args
      capabilities["goog:chromeOptions"] = chromeOpts

    case _ where browser.name.contains("Firefox"):
      capabilities["browserName"] = "firefox"
      if headless {
        capabilities["moz:firefoxOptions"] = ["args": ["-headless"]]
      }

    default:
      return false
    }

    let body: [String: Any] = [
      "capabilities": ["alwaysMatch": capabilities],
    ]

    let resp = await request("POST", path: "/session", body: body)
    if resp.success, let value = resp.value {
      // Extract sessionId from JSON response
      if let data = value.data(using: .utf8),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let sid = json["sessionId"] as? String {
        sessionId = sid
        return true
      }
    }
    return false
  }

  // MARK: - HTTP Communication

  private func request(
    _ method: String, path: String, body: [String: Any]? = nil
  ) async -> WebDriverResult {
    let urlString = "http://localhost:\(port)\(path)"
    guard let url = URL(string: urlString) else {
      return .init(success: false, value: nil, error: "Invalid URL")
    }

    var req = URLRequest(url: url, timeoutInterval: 30)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if let body {
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let httpResponse = response as? HTTPURLResponse
      let statusOK = (200..<300).contains(httpResponse?.statusCode ?? 0)

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        let text = String(data: data, encoding: .utf8) ?? ""
        return .init(success: statusOK, value: text, error: statusOK ? nil : text)
      }

      let value = json["value"]

      // Check for WebDriver error
      if let errorDict = value as? [String: Any], let errorMsg = errorDict["message"] as? String {
        if errorDict["error"] != nil {
          return .init(success: false, value: nil, error: errorMsg)
        }
      }

      // Format value as string
      let valueStr: String?
      if let s = value as? String {
        valueStr = s
      } else if let n = value as? NSNumber {
        valueStr = "\(n)"
      } else if let dict = value as? [String: Any] {
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
          valueStr = String(data: jsonData, encoding: .utf8)
        } else {
          valueStr = "\(dict)"
        }
      } else if let arr = value as? [Any] {
        if let jsonData = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted) {
          valueStr = String(data: jsonData, encoding: .utf8)
        } else {
          valueStr = "\(arr)"
        }
      } else if value == nil || value is NSNull {
        valueStr = nil
      } else {
        valueStr = "\(value!)"
      }

      return .init(success: statusOK, value: valueStr, error: statusOK ? nil : valueStr)
    } catch {
      return .init(success: false, value: nil, error: "\(error)")
    }
  }
}
