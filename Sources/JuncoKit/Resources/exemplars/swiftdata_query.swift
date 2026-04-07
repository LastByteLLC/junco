// View with @Query and #Predicate for filtering SwiftData models
import SwiftUI
import SwiftData

struct CookbookListView: View {
    @Query(sort: \Cookbook.title)
    private var cookbooks: [Cookbook]

    @Environment(\.modelContext) private var context

    var body: some View {
        List(cookbooks) { cookbook in
            VStack(alignment: .leading) {
                Text(cookbook.title).font(.headline)
                Text("\(cookbook.recipes.count) recipes").font(.caption)
            }
        }
        .toolbar {
            Button("Add") { addSample() }
        }
    }

    private func addSample() {
        let book = Cookbook(
            title: "Quick Meals",
            author: "Chef Ana",
            isbn: UUID().uuidString,
            publishedDate: .now
        )
        context.insert(book)
    }
}

func quickRecipes(maxMinutes: Int) -> Predicate<Recipe> {
    #Predicate<Recipe> { recipe in
        recipe.prepTimeMinutes <= maxMinutes
    }
}
