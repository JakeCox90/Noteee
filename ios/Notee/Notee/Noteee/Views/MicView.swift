import SwiftUI

struct MicView: View {

    var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Title
            Text("Noteee")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)

            Spacer()

            // Transcript preview
            if !viewModel.transcript.isEmpty {
                Text(viewModel.transcript)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Duration indicator during recording
            if viewModel.state == .recording {
                Text(formattedDuration(viewModel.recordingDuration))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.red)
            }

            // Mic / cancel button
            Button(action: {
                if viewModel.state == .transcribing || viewModel.state == .submitting {
                    viewModel.cancelTranscription()
                } else {
                    viewModel.toggleRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 96, height: 96)
                        .shadow(color: micButtonColor.opacity(0.4), radius: 12, x: 0, y: 4)

                    Image(systemName: micButtonIcon)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(viewModel.state == .recording ? 1.1 : 1.0)
            .animation(
                viewModel.state == .recording
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: viewModel.state == .recording
            )
            .disabled(false)
            .accessibilityLabel(micAccessibilityLabel)

            Text(micButtonLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .animation(.easeInOut, value: viewModel.transcript)
        .animation(.easeInOut, value: viewModel.state)
    }

    // MARK: - Helpers

    private var micButtonColor: Color {
        switch viewModel.state {
        case .recording:
            return .red
        case .transcribing:
            return .gray
        case .submitting:
            return .gray
        default:
            return .blue
        }
    }

    private var micButtonIcon: String {
        switch viewModel.state {
        case .recording:
            return "stop.fill"
        case .transcribing, .submitting:
            return "xmark"
        default:
            return "mic.fill"
        }
    }

    private var micButtonLabel: String {
        switch viewModel.state {
        case .idle:
            return "Tap to record"
        case .recording:
            return "Tap to stop"
        case .transcribing:
            return "Transcribing…"
        case .submitting:
            return "Submitting…"
        default:
            return ""
        }
    }

    private var micAccessibilityLabel: String {
        switch viewModel.state {
        case .recording:
            return "Stop recording"
        case .transcribing, .submitting:
            return "Cancel"
        default:
            return "Start recording"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MicView(viewModel: CaptureViewModel())
}
