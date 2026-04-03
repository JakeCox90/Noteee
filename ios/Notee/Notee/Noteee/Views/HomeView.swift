import SwiftUI
import UIKit

// MARK: - Task Item

struct TaskItem: Identifiable {
    let id = UUID()
    let notionId: String? // nil for placeholder data
    let title: String
    var isCompleted: Bool = false
    var description: String? = nil
    var priority: String = "Medium"
    var projectName: String? = nil
    var isToday: Bool = false
}

// MARK: - Colors

private let textColor = Color(red: 0.102, green: 0.204, blue: 0.263) // #1a3443
private let highColor = Color(red: 1.0, green: 0.525, blue: 0.353) // #ff865a
private let mediumColor = Color(red: 0.984, green: 0.812, blue: 0.416) // #fbcf6a
private let lowColor = Color(red: 0.169, green: 0.667, blue: 0.976) // #2baaf9
private let pillBg = Color(red: 0.800, green: 0.902, blue: 0.969) // #cce6f7
private let pillText = Color(red: 0.125, green: 0.384, blue: 0.549) // #20628c
private let bgColor = Color(red: 0.957, green: 0.973, blue: 0.976) // #f4f8f9
private let checkboxBorder = Color(red: 0.859, green: 0.859, blue: 0.859) // #dbdbdb
private let completedBg = Color(red: 0.749, green: 0.929, blue: 0.749) // #bfedbf
private let completedCheck = Color(red: 0.141, green: 0.396, blue: 0.141) // #246524
private let descriptionLabel = Color(red: 0.608, green: 0.608, blue: 0.608) // #9b9b9b
private let tagBg = Color(red: 0.349, green: 0.349, blue: 0.349).opacity(0.10) // rgba(89,89,89,0.10)
private let scrimColor = Color(red: 0.729, green: 0.729, blue: 0.729).opacity(0.40) // rgba(186,186,186,0.40)

private func playCheckboxHaptic() {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.prepare()
    generator.impactOccurred(intensity: 0.7)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
        let second = UIImpactFeedbackGenerator(style: .heavy)
        second.impactOccurred(intensity: 1.0)
    }
}

// MARK: - Home View

struct HomeView: View {

    var viewModel: CaptureViewModel
    private let api = NoteeeAPIClient.shared
    @State private var selectedTab: String = "Today"
    @State private var expandedTaskId: UUID? = nil
    @State private var isModalExpanded: Bool = false
    @State private var rowFrames: [UUID: CGRect] = [:]

    // Filter state
    @State private var showPriorityFilter = false
    @State private var showProjectFilter = false
    @State private var selectedPriorities: Set<String> = [] // empty = show all
    @State private var selectedProjects: Set<String> = [] // empty = show all
    @State private var tempPriorities: Set<String> = []
    @State private var tempProjects: Set<String> = []
    @State private var isFilterExpanded = false

    // Single source of truth — populated from Notion on launch
    @State private var highTasks_: [TaskItem] = []
    @State private var mediumTasks_: [TaskItem] = []
    @State private var lowTasks_: [TaskItem] = []
    @State private var hasLoaded = false

    private var highTasks: Binding<[TaskItem]> { $highTasks_ }
    private var mediumTasks: Binding<[TaskItem]> { $mediumTasks_ }
    private var lowTasks: Binding<[TaskItem]> { $lowTasks_ }

    var body: some View {
        ZStack(alignment: .bottom) {
            bgColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerTabs
                        .padding(.top, 8)

                    filterPills

                    // Task sections — filtered by active selections
                    VStack(spacing: 32) {
                        if shouldShowPriority("High") {
                            prioritySection(label: "High", color: highColor, tasks: highTasks)
                        }
                        if shouldShowPriority("Medium") {
                            prioritySection(label: "Medium", color: mediumColor, tasks: mediumTasks)
                        }
                        if shouldShowPriority("Low") {
                            prioritySection(label: "Low", color: lowColor, tasks: lowTasks)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTab)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPriorities)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedProjects)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 100)
                }
            }
            .blur(radius: isModalExpanded || isFilterExpanded ? 8 : 0)

            makeANoteButton
                .padding(.bottom, 16)
                .opacity(expandedTaskId != nil || showPriorityFilter || showProjectFilter ? 0 : 1)
        }
        .overlay {
            if let expandedId = expandedTaskId, let task = findTask(by: expandedId) {
                taskModalOverlay(task: task, sourceFrame: rowFrames[expandedId] ?? .zero)
            }
        }
        .overlay {
            filterModalOverlay
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadActions()
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .success {
                appendCapturedActions()
            }
        }
    }

    // MARK: - Data Loading

    private func loadActions() async {
        do {
            let actions = try await api.getActions()
            var high: [TaskItem] = []
            var medium: [TaskItem] = []
            var low: [TaskItem] = []

            for action in actions {
                let item = TaskItem(
                    notionId: action.id,
                    title: action.title,
                    isCompleted: action.status == "Done",
                    priority: action.priority.capitalized,
                    projectName: action.projectName.isEmpty ? nil : action.projectName
                )
                switch action.priority.lowercased() {
                case "high": high.append(item)
                case "low": low.append(item)
                default: medium.append(item)
                }
            }

            highTasks_ = high
            mediumTasks_ = medium
            lowTasks_ = low
        } catch {
            print("Failed to load actions: \(error)")
        }
    }

    private func appendCapturedActions() {
        let project = viewModel.matchedProject
        for action in viewModel.actions {
            let item = TaskItem(
                notionId: action.notionId,
                title: action.title,
                priority: action.priority.capitalized,
                projectName: project.isEmpty ? nil : project,
                isToday: true
            )
            switch action.priority.lowercased() {
            case "high": highTasks_.insert(item, at: 0)
            case "low": lowTasks_.insert(item, at: 0)
            default: mediumTasks_.insert(item, at: 0)
            }
        }
    }

    // MARK: - Header Tabs

    private var headerTabs: some View {
        HStack(spacing: 32) {
            tabLabel("Today")
            tabLabel("All")
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabLabel(_ label: String) -> some View {
        let isSelected = selectedTab == label
        return Text(label)
            .font(.system(size: isSelected ? 32 : 24, weight: .bold))
            .foregroundStyle(textColor)
            .opacity(isSelected ? 1 : 0.4)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTab)
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedTab = label
                }
            }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        HStack(spacing: 12) {
            filterPill(
                label: "Priority",
                icon: "line.3.horizontal.decrease",
                isActive: !selectedPriorities.isEmpty
            ) {
                tempPriorities = selectedPriorities
                showPriorityFilter = true
                isFilterExpanded = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isFilterExpanded = true
                    }
                }
            }

            filterPill(
                label: "Project",
                icon: "folder.fill",
                isActive: !selectedProjects.isEmpty
            ) {
                tempProjects = selectedProjects
                showProjectFilter = true
                isFilterExpanded = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isFilterExpanded = true
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func filterPill(label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(pillText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? pillText.opacity(0.15) : pillBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Priority Section

    private func prioritySection(label: String, color: Color, tasks: Binding<[TaskItem]>) -> some View {
        let filtered = filteredTasks(tasks)
        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)

                        Text(label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(textColor)
                    }
                    .padding(.vertical, 8)

                    VStack(spacing: 22) {
                        ForEach(Array(filtered.enumerated()), id: \.element.1.id) { filteredIndex, item in
                            let (originalIndex, _) = item
                            VStack(spacing: 22) {
                                taskRow(tasks: tasks, index: originalIndex)
                                    .transition(.opacity.combined(with: .move(edge: .top)))

                                if filteredIndex < filtered.count - 1 {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.1))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 4)
                }
            }
        }
    }

    private func taskRow(tasks: Binding<[TaskItem]>, index: Int) -> some View {
        let task = tasks.wrappedValue[index]
        return HStack(spacing: 15) {
            // Tappable checkbox
            Button {
                playCheckboxHaptic()
                withAnimation(.easeInOut(duration: 0.12)) {
                    tasks.wrappedValue[index].isCompleted.toggle()
                }
                let updated = tasks.wrappedValue[index]
                if let notionId = updated.notionId {
                    Task {
                        try? await api.updateActionStatus(
                            id: notionId,
                            status: updated.isCompleted ? "Done" : "To Do"
                        )
                    }
                }
            } label: {
                if task.isCompleted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(completedBg)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(completedCheck)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(checkboxBorder, lineWidth: 2)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
            .padding(18)
            .contentShape(Rectangle())
            .padding(-18)

            // Tappable text area — opens modal
            HStack {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                    .strikethrough(task.isCompleted, color: textColor.opacity(0.3))
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                expandTask(task.id)
            }
        }
        .padding(.horizontal, 24)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrames[task.id] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrames[task.id] = newFrame
                    }
            }
        )
        .opacity(expandedTaskId == task.id ? 0 : 1)
    }

    private func expandTask(_ id: UUID) {
        expandedTaskId = id
        isModalExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isModalExpanded = true
            }
        }
    }

    private func collapseModal() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isModalExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expandedTaskId = nil
        }
    }

    // MARK: - Filter Helpers

    private func shouldShowPriority(_ priority: String) -> Bool {
        selectedPriorities.isEmpty || selectedPriorities.contains(priority)
    }

    private func filteredTasks(_ tasks: Binding<[TaskItem]>) -> [(Int, TaskItem)] {
        tasks.wrappedValue.enumerated().filter { _, task in
            let matchesTab = selectedTab == "All" || task.isToday
            let matchesProject = selectedProjects.isEmpty || selectedProjects.contains(task.projectName ?? "")
            return matchesTab && matchesProject
        }.map { ($0.offset, $0.element) }
    }

    private var availableProjects: [String] {
        let allItems = highTasks.wrappedValue + mediumTasks.wrappedValue + lowTasks.wrappedValue
        let names = allItems.compactMap(\.projectName)
        return Array(Set(names)).sorted()
    }

    private func dismissFilter() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isFilterExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showPriorityFilter = false
            showProjectFilter = false
        }
    }

    private func confirmPriorityFilter() {
        selectedPriorities = tempPriorities
        dismissFilter()
    }

    private func confirmProjectFilter() {
        selectedProjects = tempProjects
        dismissFilter()
    }

    // MARK: - Task Modal

    private func findTask(by id: UUID) -> TaskItem? {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let task = binding.wrappedValue.first(where: { $0.id == id }) {
                return task
            }
        }
        return nil
    }

    private func toggleTask(id: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                binding.wrappedValue[idx].isCompleted.toggle()
                let updated = binding.wrappedValue[idx]
                if let notionId = updated.notionId {
                    Task {
                        try? await api.updateActionStatus(
                            id: notionId,
                            status: updated.isCompleted ? "Done" : "To Do"
                        )
                    }
                }
                return
            }
        }
    }

    private func priorityColor(for priority: String) -> Color {
        switch priority {
        case "High": return highColor
        case "Low": return lowColor
        default: return mediumColor
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.504, green: 0.547, blue: 0.935), // purple-blue
            Color(red: 0.408, green: 0.745, blue: 0.957), // blue
            Color(red: 0.957, green: 0.545, blue: 0.459), // coral
            Color(red: 0.486, green: 0.804, blue: 0.569), // green
            Color(red: 0.945, green: 0.714, blue: 0.408), // amber
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }

    @ViewBuilder
    private func taskModalOverlay(task: TaskItem, sourceFrame: CGRect) -> some View {
        GeometryReader { geo in
            let screenSize = geo.size
            let safeArea = geo.safeAreaInsets

            // Calculate where the card should be when collapsed (at the row's position)
            // Subtract 22 to account for the modal header's top padding so text aligns with the list row
            let headerPadding: CGFloat = 22
            let collapsedY = sourceFrame.minY - safeArea.top - headerPadding
            // When expanded, center vertically
            let expandedY = (screenSize.height - 310) / 2

            ZStack(alignment: .top) {
                // Light scrim
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .opacity(isModalExpanded ? 1 : 0)
                    .onTapGesture { collapseModal() }

                // Expanding card
                VStack(spacing: 0) {
                    // Row content — always visible, forms the top of the modal
                    HStack(spacing: 15) {
                        Button {
                            playCheckboxHaptic()
                            withAnimation(.easeInOut(duration: 0.12)) {
                                toggleTask(id: task.id)
                            }
                        } label: {
                            if task.isCompleted {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(completedBg)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(completedCheck)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(checkboxBorder, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(18)
                        .contentShape(Rectangle())
                        .padding(-18)

                        Text(task.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                            .strikethrough(task.isCompleted, color: textColor.opacity(0.3))

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)

                    // Expandable content — grows from 0 height
                    VStack(spacing: 0) {
                        // Divider
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 1)

                        // Description
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Description")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(descriptionLabel)

                            if let desc = task.description {
                                Text(desc)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(textColor)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)

                        // Divider
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 1)

                        // Tags
                        HStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(priorityColor(for: task.priority))
                                    .frame(width: 12, height: 12)
                                Text(task.priority)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(textColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(tagBg)
                            .clipShape(Capsule())

                            if let project = task.projectName {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(avatarColor(for: project))
                                            .frame(width: 16, height: 16)
                                        Text(String(project.prefix(1)).uppercased())
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    Text(project)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(textColor)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(tagBg)
                                .clipShape(Capsule())
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                    }
                    .frame(maxHeight: isModalExpanded ? .none : 0, alignment: .top)
                    .clipped()
                    .opacity(isModalExpanded ? 1 : 0)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: isModalExpanded ? 24 : 12))
                .shadow(
                    color: .black.opacity(isModalExpanded ? 0.12 : 0.04),
                    radius: isModalExpanded ? 24 : 4,
                    x: 0, y: 4
                )
                .padding(.horizontal, 24)
                .offset(y: isModalExpanded ? expandedY : collapsedY)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Filter Modals

    private var primaryBlue: Color { Color(red: 0.231, green: 0.706, blue: 0.965) } // #3bb4f6

    @ViewBuilder
    private var filterModalOverlay: some View {
        if showPriorityFilter {
            filterScrimAndCard {
                priorityFilterContent
            }
        } else if showProjectFilter {
            filterScrimAndCard {
                projectFilterContent
            }
        }
    }

    private func filterScrimAndCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            // Scrim
            Color.black.opacity(isFilterExpanded ? 0.08 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismissFilter() }

            // Card slides up from bottom
            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: -4)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .offset(y: isFilterExpanded ? 0 : 400)
        }
    }

    private var priorityFilterContent: some View {
        VStack(spacing: 0) {
            ForEach(["High", "Medium", "Low"], id: \.self) { priority in
                Button {
                    if tempPriorities.contains(priority) {
                        tempPriorities.remove(priority)
                    } else {
                        tempPriorities.insert(priority)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(priorityColor(for: priority))
                            .frame(width: 12, height: 12)
                        Text(priority)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(textColor)
                        Spacer()
                        // Checkbox
                        if tempPriorities.contains(priority) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(primaryBlue)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(checkboxBorder, lineWidth: 2)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                if priority != "Low" {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                }
            }

            // Confirm button
            Button(action: confirmPriorityFilter) {
                Text("Confirm")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(primaryBlue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    private var projectFilterContent: some View {
        VStack(spacing: 0) {
            ForEach(availableProjects, id: \.self) { project in
                Button {
                    if tempProjects.contains(project) {
                        tempProjects.remove(project)
                    } else {
                        tempProjects.insert(project)
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(avatarColor(for: project))
                                .frame(width: 28, height: 28)
                            Text(String(project.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(project)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(textColor)
                        Spacer()
                        // Checkbox
                        if tempProjects.contains(project) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(primaryBlue)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(checkboxBorder, lineWidth: 2)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                if project != availableProjects.last {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                }
            }

            // Confirm button
            Button(action: confirmProjectFilter) {
                Text("Confirm")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(primaryBlue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Make a Note Button

    private var makeANoteButton: some View {
        Button {
            viewModel.toggleRecording()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)

                Text("Make a Note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(lowColor)
            .clipShape(Capsule())
            .shadow(color: Color(red: 0.408, green: 0.745, blue: 0.957).opacity(0.5), radius: 32, x: 0, y: 4)
            .shadow(color: Color(red: 0.408, green: 0.745, blue: 0.957).opacity(0.5), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(viewModel: CaptureViewModel())
}
