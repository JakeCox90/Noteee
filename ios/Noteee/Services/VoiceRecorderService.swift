import AVFoundation
import Observation

@Observable
final class VoiceRecorderService {

    // MARK: - Published State

    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var durationTimer: Timer?
    private let maxDuration: TimeInterval = 60

    // MARK: - Recording Control

    /// Configures the audio session and starts the AVAudioEngine recording to a temp m4a file.
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = makeTemporaryURL()
        outputURL = url

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            try? file.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        recordingDuration = 0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingDuration += 1
            if self.recordingDuration >= self.maxDuration {
                _ = self.stopRecording()
            }
        }
    }

    /// Stops the engine and returns the URL of the recorded audio file.
    @discardableResult
    func stopRecording() -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        audioFile = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)

        return outputURL
    }

    // MARK: - Helpers

    private func makeTemporaryURL() -> URL {
        let filename = "noteee_recording_\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
