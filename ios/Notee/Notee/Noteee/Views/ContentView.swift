import SwiftUI

struct ContentView: View {

    @State private var viewModel = CaptureViewModel()

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .idle, .recording, .transcribing, .submitting:
                MicView(viewModel: viewModel)

            case .success:
                SuccessView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

            case .error:
                ErrorView(viewModel: viewModel)
                    .transition(.opacity)

            case .clarification, .newProject:
                // Shown as sheets below — keep MicView as backing
                MicView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
        .sheet(isPresented: Binding(
            get: { viewModel.state == .clarification },
            set: { if !$0 { /* dismiss handled by sheet buttons */ } }
        )) {
            ClarificationSheetView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
