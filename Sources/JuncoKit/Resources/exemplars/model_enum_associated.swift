// Enum with associated values and computed property
import Foundation

enum MediaContent {
    case article(title: String, wordCount: Int)
    case podcast(title: String, duration: TimeInterval)
    case video(title: String, resolution: String)

    var title: String {
        switch self {
        case .article(let title, _),
             .podcast(let title, _),
             .video(let title, _):
            return title
        }
    }

    var summary: String {
        switch self {
        case .article(_, let wordCount):
            return "\(wordCount) words"
        case .podcast(_, let duration):
            return "\(Int(duration / 60)) min"
        case .video(_, let resolution):
            return resolution
        }
    }
}
