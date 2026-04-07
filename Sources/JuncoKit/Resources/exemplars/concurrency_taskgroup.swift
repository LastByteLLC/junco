// TaskGroup for parallel work with collected results
import Foundation

struct Thumbnail: Sendable {
    let url: URL
    let data: Data
}

func fetchThumbnails(urls: [URL]) async throws -> [Thumbnail] {
    try await withThrowingTaskGroup(of: Thumbnail.self) { group in
        for url in urls {
            group.addTask {
                let (data, _) = try await URLSession.shared.data(from: url)
                return Thumbnail(url: url, data: data)
            }
        }

        var thumbnails: [Thumbnail] = []
        for try await thumbnail in group {
            thumbnails.append(thumbnail)
        }
        return thumbnails
    }
}
