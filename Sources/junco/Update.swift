// Update.swift — `junco update` subcommand for self-updating the binary

import ArgumentParser
import Foundation
import JuncoKit

struct Update: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update junco to the latest version from GitHub Releases."
  )

  @Flag(name: .long, help: "Check for updates without installing")
  var check = false

  func run() async throws {
    let current = JuncoVersion.current
    let checker = UpdateChecker()

    print("Current version: v\(current)")
    print("Checking for updates...")

    guard let info = await checker.forceCheck(current: current) else {
      print("You're on the latest version.")
      return
    }

    print("New version available: v\(info.version)")
    if let notes = info.releaseNotes, !notes.isEmpty {
      // Show first 3 lines of release notes
      let lines = notes.components(separatedBy: .newlines).prefix(3)
      for line in lines {
        print("  \(line)")
      }
      if notes.components(separatedBy: .newlines).count > 3 {
        print("  ...")
      }
    }

    if check {
      print("\nRun `junco update` to install.")
      return
    }

    print("")
    let updater = SelfUpdater()
    try await updater.update(to: info)
  }
}
