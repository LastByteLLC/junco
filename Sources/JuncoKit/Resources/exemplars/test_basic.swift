// Swift Testing @Suite and @Test with #expect assertions
import Testing

@Suite("Recipe Tests")
struct RecipeTests {
    let recipe = Recipe(name: "Carbonara", servings: 4, isVegetarian: false)

    @Test("Recipe has correct name")
    func recipeName() {
        #expect(recipe.name == "Carbonara")
    }

    @Test("Servings must be positive")
    func positiveServings() {
        #expect(recipe.servings > 0)
    }

    @Test("Double servings scales correctly")
    func doubleServings() {
        let doubled = recipe.scaled(by: 2)
        #expect(doubled.servings == 8)
    }
}

struct Recipe {
    let name: String
    var servings: Int
    let isVegetarian: Bool

    func scaled(by factor: Int) -> Recipe {
        Recipe(name: name, servings: servings * factor, isVegetarian: isVegetarian)
    }
}
