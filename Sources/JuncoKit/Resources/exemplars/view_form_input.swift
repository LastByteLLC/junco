// Form with TextField, Toggle, Picker, and submit Button
import SwiftUI

struct RecipeFormView: View {
    @State private var name = ""
    @State private var servings = 2
    @State private var isVegetarian = false
    @State private var category = "Dinner"

    let categories = ["Breakfast", "Lunch", "Dinner", "Dessert"]

    var body: some View {
        Form {
            Section("Details") {
                TextField("Recipe name", text: $name)
                Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                Toggle("Vegetarian", isOn: $isVegetarian)
            }
            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
            }
            Section {
                Button("Save Recipe") { save() }
                    .disabled(name.isEmpty)
            }
        }
    }

    private func save() { }
}
