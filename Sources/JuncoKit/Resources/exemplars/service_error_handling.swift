// Service with custom Error enum and do/catch pattern
import Foundation

enum RecipeServiceError: Error, LocalizedError {
    case notFound(id: Int)
    case rateLimited(retryAfter: TimeInterval)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notFound(let id): "Recipe \(id) not found"
        case .rateLimited(let t): "Rate limited, retry in \(Int(t))s"
        case .unauthorized: "Authentication required"
        }
    }
}

func loadRecipe(id: Int) async throws -> String {
    guard id > 0 else { throw RecipeServiceError.notFound(id: id) }
    return "Recipe \(id)"
}

do {
    let recipe = try await loadRecipe(id: 42)
    print(recipe)
} catch let error as RecipeServiceError {
    print(error.localizedDescription)
} catch {
    print("Unexpected: \(error)")
}
