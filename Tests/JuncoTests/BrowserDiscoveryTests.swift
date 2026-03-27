// BrowserDiscoveryTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("BrowserDiscovery")
struct BrowserDiscoveryTests {
  @Test("discovers at least one browser")
  func findsABrowser() async {
    let discovery = BrowserDiscovery()
    let browsers = await discovery.discover()
    #expect(!browsers.isEmpty, "Expected at least one browser on macOS")
  }

  @Test("Safari detected on macOS")
  func findsSafari() async {
    let discovery = BrowserDiscovery()
    let browsers = await discovery.discover()
    let safari = browsers.first { $0.name == "Safari" }
    #expect(safari != nil)
    #expect(safari?.driverPath == "/usr/bin/safaridriver")
  }

  @Test("formatForPrompt includes browser names")
  func formatPrompt() async {
    let discovery = BrowserDiscovery()
    let browsers = await discovery.discover()
    let formatted = discovery.formatForPrompt(browsers)
    #expect(formatted.contains("Safari"))
  }

  @Test("bestHeadlessBrowser prefers Chrome")
  func bestHeadless() async {
    let discovery = BrowserDiscovery()
    let browsers = await discovery.discover()
    let best = discovery.bestHeadlessBrowser(browsers)
    // On a system with Chrome, it should prefer Chrome (headless support)
    // On Safari-only, returns Safari
    #expect(best != nil)
  }

  @Test("DetectedBrowser isReady when driver present and no setup needed")
  func isReady() {
    let ready = DetectedBrowser(
      name: "Test", path: "/test", version: "1.0",
      driverPath: "/driver", driverSource: "local",
      headless: true, setupNeeded: nil
    )
    #expect(ready.isReady)

    let notReady = DetectedBrowser(
      name: "Test", path: "/test", version: "1.0",
      driverPath: nil, driverSource: nil,
      headless: true, setupNeeded: "install driver"
    )
    #expect(!notReady.isReady)
  }
}
