import Foundation

struct Project: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let prefix: String?

    init(id: String, name: String, description: String, prefix: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.prefix = prefix
    }
}
