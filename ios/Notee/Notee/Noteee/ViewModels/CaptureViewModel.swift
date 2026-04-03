import AVFoundation
import Observation
import SwiftUI

// MARK: - State

enum CaptureState: Equatable {
    case idle
    case recording
    case transcribing
    case submitting
    case success
    case clarification
    case newProject
    case error
}

// MARK: - ViewModel

@Observable
@MainActor
final class CaptureViewModel {

    // MARK: - Public State

    var state: CaptureState = .idle
    var transcript: String = ""
    var matchedProject: String = ""
    var actions: [Action] = []
    var clarificationQuestion: String = ""
    var clarificationOptions: [String] = []
    var errorMessage: String = ""

    /// Preserved for re-submission without re-recording.
    private(set) var originalTranscription: String = ""

    // MARK: - Private

    private let recorder = VoiceRecorderService()
    private let api: NoteeeAPIClient
    private var transcriptionTask: Task<Void, Never>?
    private var submissionTask: Task<Void, Never>?

    var isRecording: Bool { recorder.isRecording }
    var recordingDuration: TimeInterval { recorder.recordingDuration }

    // MARK: - Init

    init(api: NoteeeAPIClient = .shared) {
        self.api = api
    }

    // MARK: - Recording

    /// Starts or stops recording depending on current state.
    func toggleRecording() {
        if state == .recording {
            stopAndSubmit()
        } else if state == .idle {
            startRecording()
        }
    }

    private func startRecording() {
        // Check microphone permission first
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.beginRecording()
                    } else {
                        self?.setError("Microphone access is required. Please enable it in Settings.")
                    }
                }
            }
        case .denied:
            setError("Microphone access denied. Please enable it in Settings > Noteee.")
        case .granted:
            beginRecording()
        @unknown default:
            setError("Microphone permission state unknown.")
        }
    }

    private func beginRecording() {
        do {
            try recorder.startRecording()
            state = .recording
        } catch {
            setError("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    private func stopAndSubmit() {
        guard let audioURL = recorder.stopRecording() else {
            setError("No audio was recorded. Please try again.")
            return
        }
        state = .transcribing

        transcriptionTask = Task {
            await transcribeAndCapture(audioURL: audioURL)
        }
    }

    /// Cancels an in-progress transcription or submission and returns to idle.
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        submissionTask?.cancel()
        submissionTask = nil
        reset()
    }

    // MARK: - Submission

    private func transcribeAndCapture(audioURL: URL) async {
        do {
            let text = try await api.transcribe(audioURL: audioURL)
            guard !Task.isCancelled else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                setError("Couldn't transcribe — please try again.")
                return
            }
            transcript = text
            originalTranscription = text
            await submit(transcription: text)
        } catch {
            guard !Task.isCancelled else { return }
            setError(error.localizedDescription)
        }
    }

    /// Re-submits using the preserved original transcription (retry without re-recording).
    func retry() {
        guard !originalTranscription.isEmpty else {
            reset()
            return
        }
        state = .submitting
        Task {
            await submit(transcription: originalTranscription)
        }
    }

    /// Submits a capture with an optional confirmed project.
    func submit() {
        guard !originalTranscription.isEmpty else { return }
        state = .submitting
        Task {
            await submit(transcription: originalTranscription)
        }
    }

    private func submit(transcription: String, confirmedProject: String? = nil) async {
        state = .submitting
        do {
            let response = try await api.capture(transcription: transcription, confirmedProject: confirmedProject)
            guard !Task.isCancelled else { return }

            if response.success == true {
                matchedProject = response.project ?? ""
                actions = response.actions ?? []
                state = .success
            } else if response.needsClarification == true {
                clarificationQuestion = response.question ?? "Which project is this for?"
                clarificationOptions = response.options ?? []
                state = .clarification
            } else {
                let message = response.error ?? "Unexpected response from server."
                setError(message)
            }
        } catch {
            guard !Task.isCancelled else { return }
            setError(error.localizedDescription)
        }
    }

    // MARK: - Clarification

    /// Re-submits with the user-confirmed project name.
    func confirmProject(_ name: String) {
        state = .submitting
        submissionTask = Task {
            await submit(transcription: originalTranscription, confirmedProject: name)
        }
    }

    // MARK: - New Project

    /// Calls POST /api/projects then re-submits the original capture.
    func createProject(name: String) {
        state = .submitting
        Task {
            do {
                let created = try await api.createProject(name: name, description: nil)
                await submit(transcription: originalTranscription, confirmedProject: created.name)
            } catch APIError.conflict {
                // Project already exists — treat as a confirmed match
                await submit(transcription: originalTranscription, confirmedProject: name)
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Reset

    func reset() {
        state = .idle
        transcript = ""
        matchedProject = ""
        actions = []
        clarificationQuestion = ""
        clarificationOptions = []
        errorMessage = ""
        originalTranscription = ""
    }

    // MARK: - Helpers

    private func setError(_ message: String) {
        errorMessage = message
        state = .error
    }
}
