// @main App with TabView and multiple tabs
import SwiftUI

@main
struct PodcastApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Browse", systemImage: "square.grid.2x2") {
                    BrowseView()
                }
                Tab("Search", systemImage: "magnifyingglass") {
                    SearchView()
                }
                Tab("Library", systemImage: "books.vertical") {
                    LibraryView()
                }
                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
        }
    }
}

struct BrowseView: View { var body: some View { Text("Browse") } }
struct SearchView: View { var body: some View { Text("Search") } }
struct LibraryView: View { var body: some View { Text("Library") } }
struct SettingsView: View { var body: some View { Text("Settings") } }
