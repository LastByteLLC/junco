import Testing
@testable import Calc

@Suite("Calculator")
struct CalcTests {
  @Test("addition works")
  func add() {
    #expect(calculate(2, "+", 3) == 5)
  }

  @Test("subtraction works")
  func subtract() {
    #expect(calculate(10, "-", 4) == 6)
  }
}
