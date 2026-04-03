import SwiftUI

struct ClarificationSheetView: View {

    @State var viewModel: CaptureViewModel
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Question
                Text(viewModel.clarificationQuestion)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Project options
                VStack(spacing: 0) {
                    ForEach(viewModel.clarificationOptions, id: \.self) { option in
                        Button {
                            viewModel.confirmProject(option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select project: \(option)")

                        Divider()
                            .padding(.leading)
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Create new project
                Button {
                    showingNewProject = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Create new project")
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a new project")

                Spacer()
            }
            .navigationTitle("Which project?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.reset()
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheetView(viewModel: viewModel)
        }
    }
}

#Preview {
    let vm = CaptureViewModel()
    // Simulate clarification state
    return ClarificationSheetView(viewModel: vm)
}
