// Struct conforming to Identifiable and Hashable for use in collections
import Foundation

struct Recipe: Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var prepTimeMinutes: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Recipe, rhs: Recipe) -> Bool {
        lhs.id == rhs.id
    }
}

let recipes: Set<Recipe> = [
    Recipe(id: UUID(), name: "Pasta Carbonara", category: "Italian", prepTimeMinutes: 30),
    Recipe(id: UUID(), name: "Pad Thai", category: "Thai", prepTimeMinutes: 25)
]
