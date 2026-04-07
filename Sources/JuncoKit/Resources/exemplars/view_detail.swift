// Detail view as navigation destination with data display
import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recipe.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Label("\(recipe.prepTime) min", systemImage: "clock")
                    .foregroundStyle(.secondary)

                Text(recipe.instructions)
                    .font(.body)
            }
            .padding()
        }
        .toolbar {
            Button(isFavorite ? "Unfavorite" : "Favorite",
                   systemImage: isFavorite ? "heart.fill" : "heart") {
                isFavorite.toggle()
            }
        }
    }
}

struct Recipe: Identifiable, Hashable {
    let id: UUID
    let name: String
    let prepTime: Int
    let instructions: String
}
