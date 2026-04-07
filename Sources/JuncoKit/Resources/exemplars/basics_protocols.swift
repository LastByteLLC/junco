// Protocol with default implementation via extension
import Foundation

protocol Describable {
    var name: String { get }
    var category: String { get }
    func describe() -> String
}

extension Describable {
    func describe() -> String {
        "\(name) (\(category))"
    }
}

struct Ingredient: Describable {
    let name: String
    let category: String
    let calories: Int
}

struct Spice: Describable {
    let name: String
    let category = "Spice"
    let heatLevel: Int

    func describe() -> String {
        "\(name) - heat \(heatLevel)/10"
    }
}

let items: [any Describable] = [
    Ingredient(name: "Tomato", category: "Vegetable", calories: 22),
    Spice(name: "Cayenne", heatLevel: 8)
]
for item in items { print(item.describe()) }
