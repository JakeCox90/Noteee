import Foundation

// Handles both success and clarification API responses from /api/capture
struct CaptureResponse: Codable {
    // Success path
    let success: Bool?
    let project: String?
    let actions: [Action]?

    // Clarification path
    let needsClarification: Bool?
    let question: String?
    let options: [String]?
    let transcription: String?

    // Error
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case project
        case actions
        case needsClarification = "needs_clarification"
        case question
        case options
        case transcription
        case error
    }
}
