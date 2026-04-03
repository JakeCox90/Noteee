import AVFoundation
import Observation

@Observable
final class VoiceRecorderService {

    // MARK: - Published State

    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var outputURL: URL?
    private var durationTimer: Timer?
    private let maxDuration: TimeInterval = 60

    // MARK: - Recording Control

    /// Configures the audio session and starts recording to a WAV file.
    func startRecording() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true, options: [])
#endif

        let url = makeTemporaryURL()
        outputURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()

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

    /// Stops recording and returns the URL of the recorded audio file.
    @discardableResult
    func stopRecording() -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
#endif

        return outputURL
    }

    // MARK: - Helpers

    private func makeTemporaryURL() -> URL {
        let filename = "noteee_recording_\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
