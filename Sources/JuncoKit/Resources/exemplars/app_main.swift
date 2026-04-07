// @main App entry point with WindowGroup
import SwiftUI

@main
struct RecipeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Welcome to Recipes")
                .font(.title)
                .navigationTitle("Home")
        }
    }
}
