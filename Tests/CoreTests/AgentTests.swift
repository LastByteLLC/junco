import Testing
@testable import Core

@Test func versionExists() {
    #expect(Agent.version == "0.1.0")
}
