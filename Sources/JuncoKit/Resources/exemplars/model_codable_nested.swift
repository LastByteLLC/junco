// Struct with nested CodingKeys and custom Decodable init
import Foundation

struct Episode: Codable {
    let id: Int
    let title: String
    let publishedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
    }
}
