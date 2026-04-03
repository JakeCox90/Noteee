import SwiftUI

struct ProjectPickerView: View {

    var viewModel: CaptureViewModel
    @State private var showingNewProject = false
    @State private var visibleItems: Set<Int> = []

    private let avatarColors: [Color] = [
        Color(red: 0.40, green: 0.58, blue: 0.93),  // blue
        Color(red: 0.65, green: 0.45, blue: 0.85),  // purple
        Color(red: 0.93, green: 0.62, blue: 0.35),  // orange
        Color(red: 0.40, green: 0.75, blue: 0.52),  // green
        Color(red: 0.90, green: 0.45, blue: 0.55),  // pink
        Color(red: 0.35, green: 0.72, blue: 0.75),  // teal
        Color(red: 0.48, green: 0.42, blue: 0.80),  // indigo
        Color(red: 0.38, green: 0.78, blue: 0.68),  // mint
        Color(red: 0.40, green: 0.65, blue: 0.82),  // cyan
        Color(red: 0.72, green: 0.55, blue: 0.40),  // brown
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

            // Project list
            VStack(spacing: 8) {
                ForEach(Array(viewModel.clarificationOptions.enumerated()), id: \.element) { index, option in
                    Button {
                        viewModel.confirmProject(option)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(avatarColors[index % avatarColors.count].gradient)
                                    .frame(width: 34, height: 34)
                                Text(String(option.prefix(1)).uppercased())
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            Text(option)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 58)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select project: \(option)")
                    .opacity(visibleItems.contains(index) ? 1 : 0)
                    .offset(y: visibleItems.contains(index) ? 0 : 20)
                }

                // Create new project
                Button {
                    showingNewProject = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 34, height: 34)
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text("Create new project")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a new project")
                .opacity(visibleItems.contains(viewModel.clarificationOptions.count) ? 1 : 0)
                .offset(y: visibleItems.contains(viewModel.clarificationOptions.count) ? 0 : 20)
            }
            .padding(.horizontal, 20)
            .onAppear {
                let totalItems = viewModel.clarificationOptions.count + 1
                for i in 0..<totalItems {
                    withAnimation(.easeOut(duration: 0.3).delay(Double(i) * 0.15)) {
                        visibleItems.insert(i)
                    }
                }
            }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Which project?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheetView(viewModel: viewModel)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

#Preview {
    ProjectPickerView(viewModel: CaptureViewModel())
}
