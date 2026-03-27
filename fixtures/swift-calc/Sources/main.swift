// A simple calculator with an intentional bug
func calculate(_ a: Int, _ op: String, _ b: Int) -> Int {
  switch op {
  case "+": return a + b
  case "-": return a - b
  case "*": return a * b
  case "/": return a / b  // BUG: no division-by-zero check
  default: return 0
  }
}

print(calculate(10, "+", 5))
print(calculate(10, "-", 3))
print(calculate(10, "*", 2))
print(calculate(10, "/", 2))
