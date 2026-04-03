import SwiftUI
import UIKit

// MARK: - Task Item

struct TaskItem: Identifiable {
    let id = UUID()
    let notionId: String? // nil for placeholder data
    var title: String
    var isCompleted: Bool = false
    var description: String? = nil
    var priority: String = "Medium"
    var projectName: String? = nil
    var projectId: String? = nil
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
    @State private var swipeOffsets: [UUID: CGFloat] = [:]
    @State private var showDeleteConfirm = false
    @State private var deleteTargetId: UUID? = nil

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
    @State private var isLoading = false
    @State private var showContent = false

    // Modal editing state
    @State private var editingTitle: String = ""
    @State private var editingDescription: String = ""
    @State private var showModalPriorityPicker = false
    @State private var showModalProjectPicker = false
    @State private var allProjects: [Project] = [] // for project picker in modal

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

                    ZStack {
                        if isLoading {
                            loadingPlaceholder
                                .transition(.opacity)
                        }

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
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 100)
                }
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                }
                .ignoresSafeArea()
            )
            .blur(radius: isModalExpanded || isFilterExpanded || isRecording ? 8 : 0)

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
            isLoading = true
            async let actionsLoad: () = loadActions()
            async let projectsLoad: () = loadProjects()
            _ = await (actionsLoad, projectsLoad)
            withAnimation(.easeOut(duration: 0.25)) {
                isLoading = false
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .success {
                appendCapturedActions()
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = deleteTargetId {
                    deleteTask(id: id)
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTargetId = nil
            }
        } message: {
            Text("This action will be permanently deleted.")
        }
    }

    // MARK: - Data Loading

    private func loadActions() async {
        do {
            let actions = try await api.getActions()
            var allItems: [(TaskItem, Int)] = [] // (item, score) for Today ranking
            var high: [TaskItem] = []
            var medium: [TaskItem] = []
            var low: [TaskItem] = []

            for (index, action) in actions.enumerated() {
                let item = TaskItem(
                    notionId: action.id,
                    title: action.title,
                    isCompleted: action.status == "Done",
                    description: (action.description ?? "").isEmpty ? nil : action.description,
                    priority: action.priority.capitalized,
                    projectName: action.projectName.isEmpty ? nil : action.projectName,
                    projectId: (action.projectId ?? "").isEmpty ? nil : action.projectId
                )

                // Score for Today ranking:
                // "In Progress" = 1000 (always shows)
                // Priority: High = 30, Medium = 20, Low = 10
                // Recency bonus: newer items score higher (actions already sorted newest-first)
                var score = 0
                if action.status == "In Progress" { score += 1000 }
                switch action.priority.lowercased() {
                case "high": score += 30
                case "medium": score += 20
                case "low": score += 10
                default: score += 20
                }
                // Recency: first item gets max bonus, decreasing
                score += max(0, 50 - index)

                allItems.append((item, score))

                switch action.priority.lowercased() {
                case "high": high.append(item)
                case "low": low.append(item)
                default: medium.append(item)
                }
            }

            // Mark top 10 scored items (that aren't completed) as Today
            let todayLimit = 10
            let todayIds = Set(
                allItems
                    .filter { !$0.0.isCompleted }
                    .sorted { $0.1 > $1.1 }
                    .prefix(todayLimit)
                    .map { $0.0.id }
            )

            func markToday(_ items: inout [TaskItem]) {
                for i in items.indices {
                    items[i].isToday = todayIds.contains(items[i].id)
                }
            }

            markToday(&high)
            markToday(&medium)
            markToday(&low)

            highTasks_ = high
            mediumTasks_ = medium
            lowTasks_ = low
        } catch {
            print("Failed to load actions: \(error)")
        }
    }

    private func loadProjects() async {
        do {
            allProjects = try await api.getProjects()
        } catch {
            print("Failed to load projects: \(error)")
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

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 32) {
            ForEach(0..<3, id: \.self) { section in
                VStack(alignment: .leading, spacing: 10) {
                    // Priority label placeholder
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 60, height: 14)
                    }
                    .padding(.vertical, 8)

                    // Card with row placeholders
                    VStack(spacing: 0) {
                        ForEach(0..<(section == 0 ? 3 : 2), id: \.self) { row in
                            VStack(spacing: 0) {
                                HStack(spacing: 15) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.12))
                                        .frame(width: 16, height: 16)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.12))
                                        .frame(height: 14)
                                        .frame(maxWidth: row == 1 ? 180 : .infinity)
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 24)

                                if row < (section == 0 ? 2 : 1) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .phaseAnimator([false, true]) { content, pulsing in
            content.opacity(pulsing ? 0.6 : 1.0)
        } animation: { _ in
            .easeInOut(duration: 0.8)
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

                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.1.id) { filteredIndex, item in
                            let (originalIndex, _) = item
                            let isFirst = filteredIndex == 0
                            let isLast = filteredIndex == filtered.count - 1

                            taskRow(tasks: tasks, index: originalIndex, isFirst: isFirst, isLast: isLast)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 4)
                }
            }
        }
    }

    private func taskRow(tasks: Binding<[TaskItem]>, index: Int, isFirst: Bool, isLast: Bool) -> some View {
        let task = tasks.wrappedValue[index]
        let offset = swipeOffsets[task.id] ?? 0

        // Row content — defines the cell height
        let rowContent = VStack(spacing: 0) {
            HStack(spacing: 15) {
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
            .padding(.vertical, 24)

            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
            }
        }

        // The row content is the sizing reference.
        // White foreground slides; swipe color is a stationary background.
        return rowContent
            .hidden() // invisible sizing spacer
            .overlay {
                // Swipe color — stationary, exactly matches row size
                ZStack {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.925, green: 0.357, blue: 0.357))
                    .opacity(offset > 0 ? 1 : 0)

                    HStack {
                        Spacer()
                        Image(systemName: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(task.isCompleted ? Color(red: 0.965, green: 0.714, blue: 0.251) : Color(red: 0.298, green: 0.761, blue: 0.431))
                    .opacity(offset < 0 ? 1 : 0)
                }
            }
            .overlay {
                // White foreground — slides on swipe
                rowContent
                    .background(Color.white)
                    .offset(x: offset)
            }
            .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard horizontal > vertical * 1.5 else { return }
                    swipeOffsets[task.id] = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 80
                    if value.translation.width < -threshold {
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
                    } else if value.translation.width > threshold {
                        deleteTargetId = task.id
                        showDeleteConfirm = true
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipeOffsets[task.id] = 0
                    }
                }
        )
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
        if let task = findTask(by: id) {
            editingTitle = task.title
            editingDescription = task.description ?? ""
        }
        showModalPriorityPicker = false
        showModalProjectPicker = false
        expandedTaskId = id
        isModalExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isModalExpanded = true
            }
        }
    }

    private func collapseModal() {
        // Save edits before closing
        if let id = expandedTaskId {
            saveModalEdits(for: id)
        }
        showModalPriorityPicker = false
        showModalProjectPicker = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isModalExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expandedTaskId = nil
        }
    }

    private func saveModalEdits(for id: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                let task = binding.wrappedValue[idx]
                let titleChanged = editingTitle != task.title
                let descChanged = editingDescription != (task.description ?? "")

                if titleChanged {
                    binding.wrappedValue[idx].title = editingTitle
                }
                if descChanged {
                    binding.wrappedValue[idx].description = editingDescription.isEmpty ? nil : editingDescription
                }

                // Sync changes to Notion
                if let notionId = task.notionId, (titleChanged || descChanged) {
                    var fields: [String: String] = [:]
                    if titleChanged { fields["title"] = editingTitle }
                    if descChanged { fields["description"] = editingDescription }
                    Task {
                        try? await api.updateAction(id: notionId, fields: fields)
                    }
                }
                return
            }
        }
    }

    private func updateTaskPriority(id: UUID, newPriority: String) {
        // Remove from current list
        var task: TaskItem?
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                task = binding.wrappedValue[idx]
                binding.wrappedValue.remove(at: idx)
                break
            }
        }

        guard var item = task else { return }
        item.priority = newPriority

        // Add to correct list
        switch newPriority {
        case "High": highTasks_.insert(item, at: 0)
        case "Low": lowTasks_.insert(item, at: 0)
        default: mediumTasks_.insert(item, at: 0)
        }

        // Sync to Notion
        if let notionId = item.notionId {
            Task {
                try? await api.updateAction(id: notionId, fields: ["priority": newPriority.lowercased()])
            }
        }
    }

    private func updateTaskProject(id: UUID, project: Project) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                binding.wrappedValue[idx].projectName = project.name
                binding.wrappedValue[idx].projectId = project.id

                if let notionId = binding.wrappedValue[idx].notionId {
                    Task {
                        try? await api.updateAction(id: notionId, fields: ["projectId": project.id])
                    }
                }
                return
            }
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
        let visibleItems = allItems.filter { task in
            selectedTab == "All" || task.isToday
        }
        let names = visibleItems.compactMap(\.projectName)
        return Array(Set(names)).sorted()
    }

    private func priorityHasItems(_ priority: String) -> Bool {
        let tasks: [TaskItem]
        switch priority {
        case "High": tasks = highTasks.wrappedValue
        case "Low": tasks = lowTasks.wrappedValue
        default: tasks = mediumTasks.wrappedValue
        }
        return tasks.contains { task in
            let matchesTab = selectedTab == "All" || task.isToday
            let matchesProject = selectedProjects.isEmpty || selectedProjects.contains(task.projectName ?? "")
            return matchesTab && matchesProject
        }
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

    private func deleteTask(id: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                let task = binding.wrappedValue[idx]
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    binding.wrappedValue.remove(at: idx)
                }
                // Archive in Notion
                if let notionId = task.notionId {
                    Task {
                        try? await api.updateActionStatus(id: notionId, status: "Archived")
                    }
                }
                deleteTargetId = nil
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

            let headerPadding: CGFloat = 22
            let collapsedY = sourceFrame.minY - safeArea.top - headerPadding
            let expandedY = (screenSize.height - 420) / 2

            ZStack(alignment: .top) {
                // Light scrim
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .opacity(isModalExpanded ? 1 : 0)
                    .onTapGesture { collapseModal() }

                // Expanding card
                VStack(spacing: 0) {
                    // Header — editable title with checkbox
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

                        if isModalExpanded {
                            TextField("Title", text: $editingTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                                .submitLabel(.done)
                        } else {
                            Text(task.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                                .strikethrough(task.isCompleted, color: textColor.opacity(0.3))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)

                    // Expandable content
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 1)

                        // Editable description
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Description")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(descriptionLabel)

                            ZStack(alignment: .topLeading) {
                                if editingDescription.isEmpty {
                                    Text("Add a description...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(descriptionLabel.opacity(0.6))
                                        .padding(.top, 8)
                                }
                                TextEditor(text: $editingDescription)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(textColor)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 80)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)

                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 1)

                        // Tappable tags
                        HStack(spacing: 12) {
                            // Priority — tappable to cycle
                            Button {
                                showModalPriorityPicker.toggle()
                                showModalProjectPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(priorityColor(for: task.priority))
                                        .frame(width: 12, height: 12)
                                    Text(task.priority)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(textColor)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(descriptionLabel)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(showModalPriorityPicker ? primaryBlue.opacity(0.1) : tagBg)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            // Project — tappable to change
                            Button {
                                showModalProjectPicker.toggle()
                                showModalPriorityPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    if let project = task.projectName {
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
                                    } else {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(descriptionLabel)
                                        Text("Project")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(descriptionLabel)
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(descriptionLabel)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(showModalProjectPicker ? primaryBlue.opacity(0.1) : tagBg)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)

                        // Inline priority picker
                        if showModalPriorityPicker {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(height: 1)

                                ForEach(["High", "Medium", "Low"], id: \.self) { priority in
                                    Button {
                                        if let id = expandedTaskId {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                updateTaskPriority(id: id, newPriority: priority)
                                                showModalPriorityPicker = false
                                            }
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
                                            if task.priority == priority {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(primaryBlue)
                                            }
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Inline project picker
                        if showModalProjectPicker {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(height: 1)

                                ForEach(allProjects, id: \.id) { project in
                                    Button {
                                        if let id = expandedTaskId {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                updateTaskProject(id: id, project: project)
                                                showModalProjectPicker = false
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(avatarColor(for: project.name))
                                                    .frame(width: 24, height: 24)
                                                Text(String(project.name.prefix(1)).uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            Text(project.name)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(textColor)
                                            Spacer()
                                            if task.projectName == project.name {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(primaryBlue)
                                            }
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showModalPriorityPicker)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showModalProjectPicker)
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
                let hasItems = priorityHasItems(priority)
                Button {
                    guard hasItems else { return }
                    if tempPriorities.contains(priority) {
                        tempPriorities.remove(priority)
                    } else {
                        tempPriorities.insert(priority)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(hasItems ? priorityColor(for: priority) : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        Text(priority)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(hasItems ? textColor : textColor.opacity(0.3))
                        Spacer()
                        // Checkbox
                        if tempPriorities.contains(priority) && hasItems {
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
                                .stroke(hasItems ? checkboxBorder : checkboxBorder.opacity(0.4), lineWidth: 2)
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

    private var isRecording: Bool { viewModel.state == .recording }

    private var makeANoteButton: some View {
        Button {
            viewModel.toggleRecording()
        } label: {
            ZStack {
                // Expanded state — "Make a Note"
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)

                    Text("Make a Note")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .opacity(isRecording ? 0 : 1)

                // Collapsed state — X icon
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(isRecording ? 1 : 0)
            }
            .padding(.horizontal, isRecording ? 0 : 24)
            .frame(width: isRecording ? 75 : nil, height: isRecording ? 75 : 56)
            .background(isRecording ? Color(red: 0.925, green: 0.357, blue: 0.357) : lowColor)
            .clipShape(Capsule())
            .shadow(
                color: isRecording
                    ? Color(red: 0.925, green: 0.357, blue: 0.357).opacity(0.5)
                    : Color(red: 0.408, green: 0.745, blue: 0.957).opacity(0.5),
                radius: isRecording ? 16 : 32, x: 0, y: 4
            )
            .shadow(
                color: isRecording
                    ? Color(red: 0.925, green: 0.357, blue: 0.357).opacity(0.5)
                    : Color(red: 0.408, green: 0.745, blue: 0.957).opacity(0.5),
                radius: 12, x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isRecording)
    }
}

#Preview {
    HomeView(viewModel: CaptureViewModel())
}
