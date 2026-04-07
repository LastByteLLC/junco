// @Observable class for form input with validation
import Foundation
import Observation

@Observable
class RecipeFormViewModel {
    var name = ""
    var servings = 1
    var category = "Dinner"
    var isSaving = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servings > 0
    }

    var nameError: String? {
        name.isEmpty ? nil :
            name.count < 3 ? "Name must be at least 3 characters" : nil
    }

    let categories = ["Breakfast", "Lunch", "Dinner", "Dessert"]

    func save() async throws {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }
        try await Task.sleep(for: .seconds(1))
    }
}
