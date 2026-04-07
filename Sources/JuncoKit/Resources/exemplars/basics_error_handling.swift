// Custom error type, throwing function, do/try/catch
import Foundation

enum ValidationError: Error, LocalizedError {
    case tooShort(minimum: Int)
    case tooLong(maximum: Int)
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .tooShort(let min): "Must be at least \(min) characters"
        case .tooLong(let max): "Must be at most \(max) characters"
        case .invalidCharacters: "Contains invalid characters"
        }
    }
}

func validateUsername(_ name: String) throws -> String {
    guard name.count >= 3 else {
        throw ValidationError.tooShort(minimum: 3)
    }
    guard name.count <= 20 else {
        throw ValidationError.tooLong(maximum: 20)
    }
    guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
        throw ValidationError.invalidCharacters
    }
    return name
}

do {
    let username = try validateUsername("swift_dev")
    print("Valid: \(username)")
} catch {
    print("Error: \(error.localizedDescription)")
}
