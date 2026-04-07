// if/else, switch with pattern matching, for-in, and while
import Foundation

enum TrafficLight {
    case red, yellow, green
}

func action(for light: TrafficLight) -> String {
    switch light {
    case .red: "Stop"
    case .yellow: "Caution"
    case .green: "Go"
    }
}

let scores = [85, 92, 78, 95, 67]

for score in scores where score >= 90 {
    print("\(score) is an A")
}

let grade = { (score: Int) -> String in
    switch score {
    case 90...100: "A"
    case 80..<90: "B"
    case 70..<80: "C"
    default: "F"
    }
}

if let max = scores.max() {
    print("Best: \(grade(max))")
} else {
    print("No scores")
}

var countdown = 3
while countdown > 0 {
    print("\(countdown)...")
    countdown -= 1
}
