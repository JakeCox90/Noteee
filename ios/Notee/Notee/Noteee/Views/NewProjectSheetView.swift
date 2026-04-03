import SwiftUI

struct NewProjectSheetView: View {

    var viewModel: CaptureViewModel
    @State private var projectName: String = ""
    @Environment(\.dismiss) private var dismiss

    private var isSubmitDisabled: Bool {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Enter a name for your new project:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TextField("Project name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .submitLabel(.done)
                    .onSubmit {
                        if !isSubmitDisabled {
                            createProject()
                        }
                    }

                Spacer()
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(isSubmitDisabled)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func createProject() {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
        viewModel.createProject(name: name)
    }
}

#Preview {
    NewProjectSheetView(viewModel: CaptureViewModel())
}
