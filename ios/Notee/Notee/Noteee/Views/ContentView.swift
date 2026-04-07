import SwiftUI

struct ContentView: View {

    @State private var viewModel = CaptureViewModel()

    private var showingPicker: Bool {
        viewModel.state == .clarification
    }

    private var isRecordingFlow: Bool {
        viewModel.state == .recording || viewModel.state == .submitting
    }

    private var showOverlay: Bool {
        viewModel.state == .error
    }

    var body: some View {
        ZStack {
            // Home view — always present as base
            HomeView(viewModel: viewModel)
                .blur(radius: showOverlay || showingPicker ? 8 : 0)

            // Scrim for overlay states
            if showOverlay || showingPicker {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .transition(.opacity)
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
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: viewModel.state)
        .onAppear { viewModel.prefetchToken() }
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
