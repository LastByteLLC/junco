// BackgroundTasksTests.swift

import Testing
import Foundation
@testable import JuncoKit

@Suite("BackgroundTasks")
struct BackgroundTasksTests {
  @Test("BackgroundTaskRunner initializes with default tasks")
  func init_ok() async {
    let ctx = BackgroundContext(
      workingDirectory: NSTemporaryDirectory(),
      adapter: AFMAdapter(),
      domain: Domains.general
    )
    let runner = BackgroundTaskRunner(context: ctx)
    // Should not crash
    await runner.markActive()
  }

  @Test("markActive resets idle time")
  func markActive() async {
    let ctx = BackgroundContext(
      workingDirectory: NSTemporaryDirectory(),
      adapter: AFMAdapter(),
      domain: Domains.general
    )
    let runner = BackgroundTaskRunner(context: ctx)
    await runner.markActive()
    // checkAndRun should not run anything immediately (idle threshold not met)
    await runner.checkAndRun()
  }

  @Test("PhraseGenerationTask has correct thresholds")
  func phraseTask() {
    let task = PhraseGenerationTask()
    #expect(task.name == "phrase-generation")
    #expect(task.idleThreshold == 10)
    #expect(task.cooldown == 300)
  }

  @Test("ReflectionCompactionTask has correct thresholds")
  func reflectionTask() {
    let task = ReflectionCompactionTask()
    #expect(task.name == "reflection-compaction")
    #expect(task.idleThreshold == 30)
    #expect(task.cooldown == 600)
  }

  @Test("IndexFreshnessTask has correct thresholds")
  func indexTask() {
    let task = IndexFreshnessTask()
    #expect(task.name == "index-freshness")
    #expect(task.idleThreshold == 15)
    #expect(task.cooldown == 120)
  }
}
