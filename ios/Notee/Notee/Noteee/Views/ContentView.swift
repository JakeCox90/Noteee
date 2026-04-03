import SwiftUI

struct ContentView: View {

    @State private var viewModel = CaptureViewModel()

    private var showingPicker: Bool {
        viewModel.state == .clarification
    }

    private var isRecordingFlow: Bool {
        viewModel.state == .recording || viewModel.state == .transcribing || viewModel.state == .submitting
    }

    var body: some View {
        ZStack {
            // Home view — always present as base
            HomeView(viewModel: viewModel)
                .opacity(isRecordingFlow || showingPicker ? 0 : 1)
                .offset(y: showingPicker ? -200 : 0)

            // Recording overlay — mic button, transcribing, submitting states
            if isRecordingFlow {
                MicView(viewModel: viewModel)
                    .transition(.opacity)
            }

            // Success view
            if viewModel.state == .success {
                SuccessView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Error view
            if viewModel.state == .error {
                ErrorView(viewModel: viewModel)
                    .transition(.opacity)
            }

            // Project picker — fills the screen, slides up from bottom
            if showingPicker {
                ProjectPickerView(viewModel: viewModel)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: viewModel.state)
        .sheet(isPresented: Binding(
            get: { viewModel.state == .newProject },
            set: { if !$0 { viewModel.reset() } }
        )) {
            NewProjectSheetView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    ContentView()
}
