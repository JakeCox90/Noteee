import Foundation

/// Action returned from capture — includes Notion page ID when available
struct Action: Codable, Identifiable {
    var id: String { notionId ?? title }
    let notionId: String?
    let title: String
    let priority: String

    enum CodingKeys: String, CodingKey {
        case notionId = "id"
        case title
        case priority
    }
}

/// Full action fetched from Notion with all metadata
struct NotionAction: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let priority: String
    let status: String
    let projectId: String?
    let projectName: String
    let projectPrefix: String?
    let taskNumber: Int?
    let createdAt: String

    /// Human-readable task ID, e.g. "DJB-3"
    var taskId: String? {
        guard let prefix = projectPrefix, !prefix.isEmpty, let num = taskNumber else { return nil }
        return "\(prefix)-\(num)"
    }
}
