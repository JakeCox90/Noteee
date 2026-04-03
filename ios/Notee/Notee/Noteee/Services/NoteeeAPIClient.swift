import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse(statusCode: Int, message: String)
    case decodingFailed(Error)
    case networkError(Error)
    case conflict(String)
    case notFound(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .invalidResponse(_, let message):
            return message
        case .decodingFailed:
            return "Couldn't parse the server response."
        case .networkError(let error):
            return error.localizedDescription
        case .conflict(let message):
            return message
        case .notFound(let message):
            return message
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

final class NoteeeAPIClient {

    static let shared = NoteeeAPIClient()
    static let baseURL = "https://noteee-jakecox90s-projects.vercel.app"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Transcription

    /// Uploads audio to POST /api/transcribe, returns transcript text.
    func transcribe(audioURL: URL) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/api/transcribe") else {
            throw APIError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        struct TranscribeResponse: Decodable {
            let transcript: String?
            let text: String?
            let error: String?
        }

        let decoded = try decode(TranscribeResponse.self, from: data)
        let text = decoded.transcript ?? decoded.text ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APIError.invalidResponse(statusCode: 200, message: "Couldn't transcribe — please try again.")
        }
        return text
    }

    // MARK: - Capture

    /// POSTs to /api/capture and returns parsed CaptureResponse.
    func capture(transcription: String, confirmedProject: String? = nil) async throws -> CaptureResponse {
        guard let url = URL(string: "\(Self.baseURL)/api/capture") else {
            throw APIError.invalidURL
        }

        var body: [String: String] = ["transcription": transcription]
        if let confirmed = confirmedProject {
            body["confirmed_project"] = confirmed
        }

        let data = try await post(url: url, body: body)
        return try decode(CaptureResponse.self, from: data)
    }

    // MARK: - Projects

    /// GET /api/projects — returns list of active projects.
    func getProjects() async throws -> [Project] {
        guard let url = URL(string: "\(Self.baseURL)/api/projects") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        struct ProjectsResponse: Decodable {
            let projects: [Project]
        }

        let decoded = try decode(ProjectsResponse.self, from: data)
        return decoded.projects
    }

    /// POST /api/projects — creates a new project, returns the created project.
    func createProject(name: String, description: String?) async throws -> Project {
        guard let url = URL(string: "\(Self.baseURL)/api/projects") else {
            throw APIError.invalidURL
        }

        var body: [String: String] = ["name": name]
        if let desc = description {
            body["description"] = desc
        }

        let data = try await post(url: url, body: body)
        return try decode(Project.self, from: data)
    }

    // MARK: - Helpers

    private func post(url: URL, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to extract error message from body
            let message = extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            switch http.statusCode {
            case 409:
                throw APIError.conflict(message)
            case 404:
                throw APIError.notFound(message)
            default:
                throw APIError.invalidResponse(statusCode: http.statusCode, message: message)
            }
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}
