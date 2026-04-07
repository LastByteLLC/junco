// @Observable class with async load, filtered computed property, and search
import Foundation
import Observation

@Observable
class PodcastViewModel {
    var podcasts: [Podcast] = []
    var searchText = ""
    var isLoading = false
    var errorMessage: String?

    var filteredPodcasts: [Podcast] {
        guard !searchText.isEmpty else { return podcasts }
        return podcasts.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            podcasts = try await fetchPodcasts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPodcasts() async throws -> [Podcast] { [] }
}

struct Podcast: Identifiable {
    let id: UUID
    let title: String
}
