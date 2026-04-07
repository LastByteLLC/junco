// Codable enum with string raw values for JSON serialization
import Foundation

enum Priority: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case urgent
}

struct Task: Codable {
    let title: String
    let priority: Priority
}

let json = Data("""
{"title": "Review PR", "priority": "high"}
""".utf8)

let task = try JSONDecoder().decode(Task.self, from: json)
print(task.priority == .high) // true

for level in Priority.allCases {
    print(level.rawValue)
}
