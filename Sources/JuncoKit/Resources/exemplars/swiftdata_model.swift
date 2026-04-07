// @Model class with @Attribute and @Relationship
import Foundation
import SwiftData

@Model
class Cookbook {
    var title: String
    var author: String
    @Attribute(.unique) var isbn: String
    var publishedDate: Date

    @Relationship(deleteRule: .cascade, inverse: \Recipe.cookbook)
    var recipes: [Recipe] = []

    init(title: String, author: String, isbn: String, publishedDate: Date) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.publishedDate = publishedDate
    }
}

@Model
class Recipe {
    var name: String
    var prepTimeMinutes: Int
    var cookbook: Cookbook?

    init(name: String, prepTimeMinutes: Int, cookbook: Cookbook? = nil) {
        self.name = name
        self.prepTimeMinutes = prepTimeMinutes
        self.cookbook = cookbook
    }
}
