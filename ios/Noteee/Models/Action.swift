import Foundation

struct Action: Codable, Identifiable {
    var id: String { title }
    let title: String
    let priority: String
}
