import AVFoundation
import Observation

// MARK: - DeepGram Response Types

private struct DeepgramResponse: Decodable {
    let type: String?
    let channel: Channel?
    let isFinal: Bool?
    let speechFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case type, channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]?
    }

    struct Alternative: Decodable {
        let transcript: String?
    }
}

// MARK: - Service

@Observable
@MainActor
final class DeepgramStreamingService {

    // MARK: - Public State

    var finalizedText: String = ""
    var interimText: String = ""
    var isStreaming: Bool = false
    var error: Error?

    var liveTranscript: String {
        let finalized = finalizedText.trimmingCharacters(in: .whitespaces)
        let interim = interimText.trimmingCharacters(in: .whitespaces)
        if finalized.isEmpty { return interim }
        if interim.isEmpty { return finalized }
        return finalized + " " + interim
    }

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var keepAliveTimer: Timer?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var outputFormat: AVAudioFormat?

    /// Bounded queue for audio data waiting to be sent. Capped at 50 buffers to
    /// prevent unbounded memory growth during network hiccups.
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private static let maxQueueDepth = 50

    private static let sampleRate: Double = 48000
    private static let wsURL = "wss://api.deepgram.com/v1/listen?model=nova-3&encoding=linear16&sample_rate=48000&channels=1&punctuate=true&interim_results=true&smart_format=true&endpointing=300"

    // MARK: - Start

    func start(token: String) throws {
        teardown()

        // Audio session
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true, options: [])
        #endif

        // Audio engine setup
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Output format: PCM Int16, 48kHz, mono
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw DeepgramError.audioSetupFailed("Could not create output audio format")
        }
        outputFormat = outFormat

        // Pre-create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
            throw DeepgramError.audioSetupFailed("Could not create audio converter")
        }
        audioConverter = converter

        // WebSocket
        guard let url = URL(string: Self.wsURL) else {
            throw DeepgramError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let wsTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask = wsTask
        wsTask.resume()
        #if DEBUG
        print("[DeepGram] WebSocket opened, input format: \(inputFormat), output format: \(outFormat)")
        #endif

        // Set up bounded async stream for serialised audio delivery.
        // The audio tap enqueues converted PCM frames; a dedicated Task drains
        // the stream and sends to the WebSocket sequentially, so no frames are
        // dropped during momentary network back-pressure.
        var continuation: AsyncStream<Data>.Continuation?
        let audioStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(Self.maxQueueDepth)) { cont in
            continuation = cont
        }
        audioContinuation = continuation

        // Consumer: drain the stream and send each buffer in order.
        let wsRef = wsTask
        sendTask = Task.detached { [weak self] in
            for await data in audioStream {
                guard self != nil else { break }
                try? await wsRef.send(.data(data))
            }
        }

        // Install tap — runs on real-time audio thread
        let converterRef = converter
        let outFormatRef = outFormat
        let capturedContinuation = continuation

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            // Convert Float32 → Int16
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outFormatRef.sampleRate / buffer.format.sampleRate
            )
            guard frameCapacity > 0, let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormatRef,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            let status = converterRef.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, convertedBuffer.frameLength > 0 else { return }

            // Extract raw bytes
            let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers
            guard let ptr = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return }
            let data = Data(bytes: ptr, count: Int(audioBuffer.mDataByteSize))

            // Enqueue for serial delivery — .bufferingNewest policy drops oldest
            // frames only when the queue is full (50 buffers ≈ ~2 seconds of audio),
            // which is far better than the previous drop-on-every-in-flight behaviour.
            capturedContinuation?.yield(data)
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        #if DEBUG
        print("[DeepGram] Audio engine started")
        #endif

        // Start receive loop
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // KeepAlive timer — every 5 seconds
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak wsRef] _ in
            guard let ws = wsRef else { return }
            Task {
                try? await ws.send(.string("{\"type\":\"KeepAlive\"}"))
            }
        }

        isStreaming = true
    }

    // MARK: - Stop

    /// Stops streaming and returns the final transcript.
    func stop() async -> String {
        // Stop keepAlive
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        // Stop audio tap first so no new frames are enqueued
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioConverter = nil
        outputFormat = nil

        // Finish the audio stream so the send consumer exits cleanly
        audioContinuation?.finish()
        audioContinuation = nil
        // Wait for in-flight sends to drain before closing the WebSocket
        await sendTask?.value
        sendTask = nil

        // Flush remaining audio
        if let ws = webSocketTask {
            try? await ws.send(.string("{\"type\":\"Finalize\"}"))

            // Wait up to 2 seconds for final results
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            try? await ws.send(.string("{\"type\":\"CloseStream\"}"))
            ws.cancel(with: .normalClosure, reason: nil)
        }
        webSocketTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        isStreaming = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
        #endif

        let result = liveTranscript
        return result
    }

    // MARK: - Reset

    /// Immediately tears down audio engine, WebSocket, and timers without the
    /// graceful Finalize/CloseStream handshake. Safe to call before `start()`
    /// to ensure no stale session interferes.
    func teardown() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioConverter = nil
        outputFormat = nil

        audioContinuation?.finish()
        audioContinuation = nil
        sendTask?.cancel()
        sendTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        isStreaming = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
        #endif

        finalizedText = ""
        interimText = ""
        error = nil
    }

    func reset() {
        finalizedText = ""
        interimText = ""
        error = nil
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let ws = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    parseResponse(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        parseResponse(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                    #if DEBUG
                    print("[DeepGram] Receive error: \(error)")
                    #endif
                }
                break
            }
        }
    }

    private func parseResponse(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            guard response.type == "Results" else {
                #if DEBUG
                print("[DeepGram] Non-results message: \(response.type ?? "unknown")")
                #endif
                return
            }

            let transcript = response.channel?.alternatives?.first?.transcript ?? ""
            #if DEBUG
            print("[DeepGram] Transcript (final=\(response.isFinal ?? false)): \"\(transcript)\"")
            #endif

            if response.isFinal == true {
                if !transcript.isEmpty {
                    if !finalizedText.isEmpty {
                        finalizedText += " "
                    }
                    finalizedText += transcript
                }
                interimText = ""
            } else {
                interimText = transcript
            }
        } catch {
            // Non-Results messages (Metadata, SpeechStarted, etc.) — ignore
        }
    }
}

// MARK: - Errors

enum DeepgramError: LocalizedError {
    case audioSetupFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .audioSetupFailed(let msg): return msg
        case .invalidURL: return "Invalid DeepGram WebSocket URL"
        }
    }
}
