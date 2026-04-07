// Codable struct with Identifiable conformance and UUID primary key
import Foundation

struct Podcast: Codable, Identifiable {
    let id: UUID
    var title: String
    var author: String
    var episodeCount: Int
    var isFeatured: Bool

    var displayTitle: String {
        isFeatured ? "\(title) *" : title
    }
}

let data = try JSONEncoder().encode(
    Podcast(
        id: UUID(),
        title: "Swift Talk",
        author: "objc.io",
        episodeCount: 240,
        isFeatured: true
    )
)
let decoded = try JSONDecoder().decode(Podcast.self, from: data)
