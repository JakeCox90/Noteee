import AVFoundation
import Observation
import SwiftUI

// MARK: - State

enum CaptureState: Equatable {
    case idle
    case recording
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

    /// Set by HomeView with all available project names before showing picker.
    var availableProjectNames: [String] = []

    // MARK: - Live Transcript (from DeepGram streaming)

    var liveTranscript: String { deepgram.liveTranscript }

    // MARK: - Private

    private let deepgram = DeepgramStreamingService()
    private let api: NoteeeAPIClient
    private var submissionTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private let maxDuration: TimeInterval = 60

    /// Pre-fetched Deepgram token so recording can start immediately without
    /// waiting for a network round-trip after the user taps record.
    private var cachedToken: String?
    private var tokenPrefetchTask: Task<Void, Never>?

    var isRecording: Bool { deepgram.isStreaming }
    private(set) var recordingDuration: TimeInterval = 0

    // MARK: - Init

    init(api: NoteeeAPIClient = .shared) {
        self.api = api
    }

    // MARK: - Token Pre-fetch

    /// Kick off a background token fetch so it is ready before the user taps record.
    /// Safe to call multiple times — a fetch already in flight will not be duplicated.
    /// Call from the view's `onAppear`.
    func prefetchToken() {
        guard cachedToken == nil, tokenPrefetchTask == nil else { return }
        tokenPrefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await self.api.getDeepgramToken()
                self.cachedToken = token
                #if DEBUG
                print("[CaptureViewModel] Deepgram token pre-fetched successfully")
                #endif
            } catch {
                // Non-fatal — beginRecording() will fetch on demand as a fallback
                #if DEBUG
                print("[CaptureViewModel] Token pre-fetch failed (will retry on record): \(error)")
                #endif
            }
            self.tokenPrefetchTask = nil
        }
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
        state = .recording
        recordingDuration = 0
        deepgram.teardown()

        Task {
            do {
                let token = try await resolveToken()
                guard state == .recording else { return } // cancelled while fetching token
                try deepgram.start(token: token)
                startDurationTimer()
                // Pre-fetch a fresh token in the background for the next recording
                cachedToken = nil
                prefetchToken()
            } catch {
                setError("Couldn't start recording: \(error.localizedDescription)")
            }
        }
    }

    /// Returns the cached token immediately if available, otherwise fetches on demand.
    private func resolveToken() async throws -> String {
        // If a pre-fetch is in flight, wait briefly for it to complete
        if let prefetch = tokenPrefetchTask {
            await prefetch.value
        }
        if let token = cachedToken {
            #if DEBUG
            print("[CaptureViewModel] Using pre-fetched Deepgram token")
            #endif
            return token
        }
        // Fallback: fetch on demand (original behaviour)
        #if DEBUG
        print("[CaptureViewModel] No cached token — fetching on demand")
        #endif
        return try await api.getDeepgramToken()
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordingDuration += 1
                if self.recordingDuration >= self.maxDuration {
                    self.stopAndSubmit()
                }
            }
        }
    }

    private func stopAndSubmit() {
        durationTimer?.invalidate()
        durationTimer = nil

        // Grab transcript immediately — don't wait for Finalize flush
        let currentText = deepgram.liveTranscript
        guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { _ = await deepgram.stop() }
            setError("No speech detected. Please try again.")
            return
        }
        transcript = currentText
        originalTranscription = currentText
        clarificationOptions = availableProjectNames
        state = .clarification

        // Stop streaming in background
        Task { _ = await deepgram.stop() }
    }

    /// Submits a typed note instead of a voice recording. Mirrors the voice flow:
    /// the text is treated as the transcript and routed through AI for project + action extraction.
    func submitTypedNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript = trimmed
        originalTranscription = trimmed
        clarificationOptions = availableProjectNames
        state = .clarification
    }

    /// Cancels an in-progress recording or submission and returns to idle.
    func cancelTranscription() {
        submissionTask?.cancel()
        submissionTask = nil
        durationTimer?.invalidate()
        durationTimer = nil
        deepgram.teardown()
        reset()
    }

    // MARK: - Submission

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
                #if DEBUG
                print("[Noteee] Capture success — project: \(response.project ?? "nil"), actions: \(actions.count)")
                #endif
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
            #if DEBUG
            print("[Noteee] Capture error: \(error)")
            #endif
            setError(error.localizedDescription)
        }
    }

    // MARK: - Clarification

    /// Submits with the user-confirmed project name. Transcript is already available.
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
        recordingDuration = 0
        deepgram.reset()
    }

    // MARK: - Helpers

    private func setError(_ message: String) {
        errorMessage = message
        state = .error
    }
}
