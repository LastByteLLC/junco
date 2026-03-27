// WebDriverClientTests.swift — Unit + integration tests for WebDriver
//
// Unit tests: verify request/response formatting, session logic
// Integration tests: actual browser automation (requires Chrome, opt-in)

import Testing
import Foundation
@testable import JuncoKit

// MARK: - Unit Tests (no browser needed)

@Suite("WebDriverClient.Unit")
struct WebDriverUnitTests {

  @Test("WebDriverResult success")
  func resultSuccess() {
    let r = WebDriverResult(success: true, value: "hello", error: nil)
    #expect(r.success)
    #expect(r.value == "hello")
    #expect(r.error == nil)
  }

  @Test("WebDriverResult failure")
  func resultFailure() {
    let r = WebDriverResult(success: false, value: nil, error: "session not created")
    #expect(!r.success)
    #expect(r.error == "session not created")
  }

  @Test("DetectedBrowser for Chrome includes headless")
  func chromeHeadless() {
    let chrome = DetectedBrowser(
      name: "Google Chrome", path: "/Applications/Google Chrome.app",
      version: "146.0", driverPath: "/usr/local/bin/chromedriver",
      driverSource: "local", headless: true, setupNeeded: nil
    )
    #expect(chrome.headless)
    #expect(chrome.isReady)
  }

  @Test("DetectedBrowser for Safari no headless")
  func safariNoHeadless() {
    let safari = DetectedBrowser(
      name: "Safari", path: "/Applications/Safari.app",
      version: "26.3", driverPath: "/usr/bin/safaridriver",
      driverSource: "builtin", headless: false, setupNeeded: nil
    )
    #expect(!safari.headless)
    #expect(safari.isReady)
  }

  @Test("client initializes with port")
  func initWithPort() async {
    let browser = DetectedBrowser(
      name: "Google Chrome", path: "/test", version: "1.0",
      driverPath: nil, driverSource: nil, headless: true, setupNeeded: nil
    )
    let client = WebDriverClient(browser: browser, port: 9999)
    let active = await client.isActive
    #expect(!active)  // Not started yet
  }
}

// MARK: - Integration Tests (requires Chrome + chromedriver)
// These tests actually launch a browser. Run with:
//   swift test --filter WebDriverIntegration

@Suite("WebDriverClient.Integration",
       .enabled(if: FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app")))
struct WebDriverIntegrationTests {

  private func makeChromeClient() async -> WebDriverClient? {
    let discovery = BrowserDiscovery()
    let browsers = await discovery.discover()
    guard let chrome = browsers.first(where: { $0.name == "Google Chrome" }) else {
      return nil
    }
    return WebDriverClient(browser: chrome, port: 4460)
  }

  @Test("creates session and navigates")
  func navigateTest() async throws {
    guard let client = await makeChromeClient() else {
      return  // Chrome not available
    }
    let started = await client.start(headless: true)
    guard started else {
      // chromedriver version mismatch or not available — skip gracefully
      return
    }

    let nav = await client.navigate(to: "https://example.com")
    #expect(nav.success)

    let title = await client.title()
    #expect(title == "Example Domain")

    await client.stop()
  }

  @Test("executes JavaScript")
  func executeJSTest() async throws {
    guard let client = await makeChromeClient() else { return }
    guard await client.start(headless: true) else { return }

    _ = await client.navigate(to: "https://example.com")
    let result = await client.executeJS("return 2 + 2")
    #expect(result.success)
    #expect(result.value == "4")

    await client.stop()
  }

  @Test("queries DOM elements")
  func domQueryTest() async throws {
    guard let client = await makeChromeClient() else { return }
    guard await client.start(headless: true) else { return }

    _ = await client.navigate(to: "https://example.com")

    let text = await client.queryText(selector: "h1")
    #expect(text == "Example Domain")

    let count = await client.queryCount(selector: "p")
    #expect(count != nil && count! > 0)

    await client.stop()
  }

  @Test("takes screenshot")
  func screenshotTest() async throws {
    guard let client = await makeChromeClient() else { return }
    guard await client.start(headless: true) else { return }

    _ = await client.navigate(to: "https://example.com")
    let screenshot = await client.screenshot()
    #expect(screenshot != nil)
    #expect(screenshot!.count > 100)  // Base64 PNG should be substantial

    await client.stop()
  }
}

// MARK: - Safari Integration Tests

@Suite("WebDriverClient.Safari",
       .enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/safaridriver")))
struct WebDriverSafariTests {

  @Test("Safari session creates and navigates")
  func safariNavigate() async throws {
    let safari = DetectedBrowser(
      name: "Safari", path: "/Applications/Safari.app",
      version: "26.3", driverPath: "/usr/bin/safaridriver",
      driverSource: "builtin", headless: false, setupNeeded: nil
    )
    let client = WebDriverClient(browser: safari, port: 4461)
    let started = await client.start(headless: false)  // Safari doesn't support headless
    guard started else { return }  // Remote automation might not be enabled

    let nav = await client.navigate(to: "https://example.com")
    #expect(nav.success)

    let title = await client.title()
    #expect(title == "Example Domain")

    await client.stop()
  }
}
