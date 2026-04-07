// Optional binding, guard let, nil coalescing, and optional chaining
import Foundation

struct UserProfile {
    var displayName: String?
    var bio: String?
    var website: URL?
}

func greet(_ profile: UserProfile?) -> String {
    guard let profile else {
        return "Hello, guest!"
    }
    let name = profile.displayName ?? "Anonymous"
    return "Hello, \(name)!"
}

func websiteHost(_ profile: UserProfile?) -> String {
    if let host = profile?.website?.host() {
        return host
    }
    return "No website"
}

let profile = UserProfile(
    displayName: "Alice",
    bio: nil,
    website: URL(string: "https://example.com")
)
let greeting = greet(profile)
let bio = profile.bio ?? "No bio provided"
let host = websiteHost(profile)
