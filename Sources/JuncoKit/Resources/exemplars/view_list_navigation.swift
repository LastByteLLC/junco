// NavigationStack with List, NavigationLink, and async .task loading
import SwiftUI

struct PodcastListView: View {
    @State private var podcasts: [Podcast] = []

    var body: some View {
        NavigationStack {
            List(podcasts) { podcast in
                NavigationLink(value: podcast) {
                    VStack(alignment: .leading) {
                        Text(podcast.title).font(.headline)
                        Text(podcast.author).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Podcasts")
            .navigationDestination(for: Podcast.self) { podcast in
                Text(podcast.title)
            }
            .task { await loadPodcasts() }
        }
    }

    private func loadPodcasts() async { }
}

struct Podcast: Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
}
