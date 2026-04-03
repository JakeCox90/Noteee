import SwiftUI

struct ErrorView: View {

    @State var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)
            }

            // Error message
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title3.bold())

                Text(viewModel.errorMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                // Retry — only shown if there is a transcript to re-submit
                if !viewModel.originalTranscription.isEmpty {
                    Button {
                        viewModel.retry()
                    } label: {
                        Text("Try Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Retry submitting with existing transcript")
                }

                // Reset — always available
                Button {
                    viewModel.reset()
                } label: {
                    Text("Start Over")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Discard and return to mic screen")
            }

            Spacer(minLength: 8)
        }
        .padding(.top)
    }
}

#Preview {
    let vm = CaptureViewModel()
    return ErrorView(viewModel: vm)
}
