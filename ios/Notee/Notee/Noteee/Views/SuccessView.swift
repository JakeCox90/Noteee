import SwiftUI

struct SuccessView: View {

    @State var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }

            // Project name
            VStack(spacing: 8) {
                Text("Saved to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.matchedProject)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }

            // Actions list
            if !viewModel.actions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions extracted")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.actions) { action in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checkmark.square")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)

                                    Text(action.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    PriorityBadge(priority: action.priority)
                                }
                                .padding()

                                if action.id != viewModel.actions.last?.id {
                                    Divider()
                                        .padding(.leading)
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
            }

            Spacer()

            // Done button
            Button {
                viewModel.reset()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .accessibilityLabel("Done — return to mic screen")

            Spacer(minLength: 8)
        }
        .padding(.top)
    }
}

// MARK: - Priority Badge

private struct PriorityBadge: View {

    let priority: String

    var body: some View {
        Text(priority)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch priority.lowercased() {
        case "high":    return .red
        case "medium":  return .orange
        case "low":     return .green
        default:        return .secondary
        }
    }
}

#Preview {
    let vm = CaptureViewModel()
    return SuccessView(viewModel: vm)
}
