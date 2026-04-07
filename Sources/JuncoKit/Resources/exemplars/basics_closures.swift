// Closure syntax, trailing closures, map, filter, and sorted
import Foundation

let temperatures = [72.0, 85.5, 68.3, 91.2, 77.8]

let celsius = temperatures.map { ($0 - 32) * 5 / 9 }

let hot = temperatures.filter { $0 > 80.0 }

let sorted = temperatures.sorted { $0 < $1 }

let names = ["Charlie", "Alice", "Bob"]
let sortedNames = names.sorted(by: <)

let formatted = temperatures.map { temp -> String in
    let c = (temp - 32) * 5 / 9
    return String(format: "%.1f C", c)
}

func applyTransform(_ values: [Double],
                    using transform: (Double) -> Double) -> [Double] {
    values.map(transform)
}

let doubled = applyTransform(temperatures) { $0 * 2 }
