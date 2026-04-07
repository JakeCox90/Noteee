import SwiftUI
import UIKit


// MARK: - Task Item

struct TaskItem: Identifiable {
    let id: UUID
    let notionId: String?
    var title: String
    var isCompleted: Bool = false
    var description: String? = nil
    var priority: String = "Medium"
    var projectName: String? = nil
    var projectId: String? = nil
    var isToday: Bool = false
    var createdAt: Date? = nil
    var taskId: String? = nil

    init(id: UUID = UUID(), notionId: String? = nil, title: String, isCompleted: Bool = false, description: String? = nil, priority: String = "Medium", projectName: String? = nil, projectId: String? = nil, isToday: Bool = false, createdAt: Date? = nil, taskId: String? = nil) {
        self.id = id
        self.notionId = notionId
        self.title = title
        self.isCompleted = isCompleted
        self.description = description
        self.priority = priority
        self.projectName = projectName
        self.projectId = projectId
        self.isToday = isToday
        self.createdAt = createdAt
        self.taskId = taskId
    }
}


// MARK: - Colors

private let textColor = Color(red: 0.102, green: 0.204, blue: 0.263) // #1a3443
private let highColor = Color(red: 1.0, green: 0.525, blue: 0.353) // #ff865a
private let mediumColor = Color(red: 0.984, green: 0.812, blue: 0.416) // #fbcf6a
private let lowColor = Color(red: 0.169, green: 0.667, blue: 0.976) // #2baaf9
private let pillBg = Color.black.opacity(0.1)
private let pillText = Color(red: 0.102, green: 0.204, blue: 0.263) // matches textColor (selected tab)
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

// MARK: - Scroll View Gesture Manager
//
// Installs UIKit gesture recognizers on the nearest UIScrollView ancestor.
// UIKit's gestureRecognizerShouldBegin properly distinguishes horizontal swipe
// from vertical scroll — something SwiftUI's DragGesture cannot do.
// UILongPressGestureRecognizer naturally coexists with scroll (finger movement
// cancels the long press, so scroll works unimpeded).

private struct ScrollViewGestureManager: UIViewRepresentable {
    let rowFrames: [UUID: CGRect]
    let railFrame: CGRect
    @Binding var reorderTaskId: UUID?
    @Binding var reorderTranslation: CGFloat
    @Binding var reorderSwapOffset: CGFloat
    @Binding var swipeOffsets: [UUID: CGFloat]
    var onReorderCheck: (UUID) -> Void
    var onSwipeCommit: (UUID, CGFloat) -> Void
    var onTabSwipe: ((CGFloat) -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.install(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.rowFrames = rowFrames
        context.coordinator.railFrame = railFrame
        context.coordinator.onReorderCheck = onReorderCheck
        context.coordinator.onSwipeCommit = onSwipeCommit
        context.coordinator.onTabSwipe = onTabSwipe
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            reorderTaskId: $reorderTaskId,
            reorderTranslation: $reorderTranslation,
            reorderSwapOffset: $reorderSwapOffset,
            swipeOffsets: $swipeOffsets
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let reorderTaskId: Binding<UUID?>
        let reorderTranslation: Binding<CGFloat>
        let reorderSwapOffset: Binding<CGFloat>
        let swipeOffsets: Binding<[UUID: CGFloat]>
        var rowFrames: [UUID: CGRect] = [:]
        var railFrame: CGRect = .zero
        var onReorderCheck: ((UUID) -> Void)?
        var onSwipeCommit: ((UUID, CGFloat) -> Void)?
        var onTabSwipe: ((CGFloat) -> Void)?

        weak var scrollView: UIScrollView?
        weak var longPressGesture: UILongPressGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        var isInstalled = false
        var isBackgroundSwipe = false
        var initialReorderY: CGFloat = 0
        var activeSwipeRowId: UUID?

        init(
            reorderTaskId: Binding<UUID?>,
            reorderTranslation: Binding<CGFloat>,
            reorderSwapOffset: Binding<CGFloat>,
            swipeOffsets: Binding<[UUID: CGFloat]>
        ) {
            self.reorderTaskId = reorderTaskId
            self.reorderTranslation = reorderTranslation
            self.reorderSwapOffset = reorderSwapOffset
            self.swipeOffsets = swipeOffsets
        }

        func install(from view: UIView) {
            guard !isInstalled else { return }
            var current: UIView? = view
            while let v = current {
                if let sv = v as? UIScrollView {
                    scrollView = sv
                    break
                }
                current = v.superview
            }
            guard let scrollView = scrollView else { return }

            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            lp.minimumPressDuration = 0.5
            lp.cancelsTouchesInView = false
            lp.delegate = self
            scrollView.addGestureRecognizer(lp)
            longPressGesture = lp

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.cancelsTouchesInView = false
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
            panGesture = pan

            isInstalled = true
        }

        // MARK: Long Press → Reorder

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            switch gesture.state {
            case .began:
                let global = gesture.location(in: nil)
                if let taskId = findTaskId(at: global) {
                    initialReorderY = gesture.location(in: scrollView).y
                    reorderTaskId.wrappedValue = taskId
                    reorderTranslation.wrappedValue = 0
                    reorderSwapOffset.wrappedValue = 0
                    scrollView.isScrollEnabled = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            case .changed:
                guard let taskId = reorderTaskId.wrappedValue else { return }
                let currentY = gesture.location(in: scrollView).y
                reorderTranslation.wrappedValue = currentY - initialReorderY
                onReorderCheck?(taskId)
            case .ended, .cancelled, .failed:
                guard reorderTaskId.wrappedValue != nil else { return }
                scrollView.isScrollEnabled = true
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    reorderTaskId.wrappedValue = nil
                    reorderTranslation.wrappedValue = 0
                    reorderSwapOffset.wrappedValue = 0
                }
            default: break
            }
        }

        // MARK: Pan → Swipe

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard reorderTaskId.wrappedValue == nil else { return }
            guard let scrollView = scrollView else { return }
            switch gesture.state {
            case .began:
                let global = gesture.location(in: nil)
                let rowId = findTaskId(at: global)
                activeSwipeRowId = rowId
                isBackgroundSwipe = (rowId == nil)
            case .changed:
                if isBackgroundSwipe { return }
                guard let rowId = activeSwipeRowId else { return }
                let tx = gesture.translation(in: scrollView).x
                swipeOffsets.wrappedValue[rowId] = tx
            case .ended:
                if isBackgroundSwipe {
                    let tx = gesture.translation(in: scrollView).x
                    if abs(tx) > 50 {
                        onTabSwipe?(tx)
                    }
                    isBackgroundSwipe = false
                    return
                }
                guard let rowId = activeSwipeRowId else { return }
                let tx = gesture.translation(in: scrollView).x
                onSwipeCommit?(rowId, tx)
                activeSwipeRowId = nil
            case .cancelled, .failed:
                isBackgroundSwipe = false
                if let rowId = activeSwipeRowId {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipeOffsets.wrappedValue[rowId] = 0
                    }
                    activeSwipeRowId = nil
                }
            default: break
            }
        }

        // MARK: Helpers

        func findTaskId(at globalPoint: CGPoint) -> UUID? {
            for (id, frame) in rowFrames where frame.contains(globalPoint) {
                return id
            }
            return nil
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer == panGesture {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
                // Never begin if the touch started inside the project rail —
                // the rail has its own horizontal scroll and must not feed the
                // tab-swipe detector.
                let loc = pan.location(in: nil)
                if railFrame != .zero && railFrame.contains(loc) { return false }
                let v = pan.velocity(in: scrollView)
                return abs(v.x) > abs(v.y) * 1.5 && abs(v.x) > 50
            }
            if gestureRecognizer == longPressGesture {
                let loc = gestureRecognizer.location(in: nil)
                return findTaskId(at: loc) != nil
            }
            return true
        }
    }
}

// MARK: - Home View

struct HomeView: View {

    var viewModel: CaptureViewModel
    private let api = NoteeeAPIClient.shared
    @State private var selectedTab: String = "All"
    @State private var showChronological: Bool = false
    /// Priority section labels the user has collapsed by tapping the header.
    @State private var collapsedSections: Set<String> = []
    /// Bumped whenever the user reorders the project rail — forces the
    /// `railProjects` computed property to re-read from ProjectOrder.
    @State private var projectOrderRev: Int = 0
    @State private var expandedTaskId: UUID? = nil
    @State private var isModalExpanded: Bool = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var swipeOffsets: [UUID: CGFloat] = [:]
    @State private var showDeleteConfirm = false
    @State private var deleteTargetId: UUID? = nil

    // Typed note modal (secondary text-input flow)
    @State private var showTypedNoteModal = false
    @State private var typedNoteText = ""
    @State private var typedNoteDescription = ""
    @FocusState private var typedNoteFocused: Bool
    @FocusState private var typedNoteDescriptionFocused: Bool

    // Project detail state — when set, the Today tab morphs into a color-themed
    // single-project view. `previousProjectFilter` preserves any filter the
    // user had active before drilling in, so back-navigation restores it.
    @State private var focusedProject: Project? = nil
    @State private var previousProjectFilter: Set<String> = []

    // Global frame of the project rail — used by the gesture manager to
    // ignore horizontal swipes that originate inside the rail, so the rail's
    // own horizontal scroll doesn't crash into the tab-swipe detector.
    @State private var railFrame: CGRect = .zero

    // Drag reorder state (driven by UIKit gesture manager)
    @State private var reorderTaskId: UUID? = nil
    @State private var reorderTranslation: CGFloat = 0
    @State private var reorderSwapOffset: CGFloat = 0
    @State private var lastSwapTime: Date = .distantPast
    @State private var pendingCrossSectionCorrection = false

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
    @State private var completedTasks_: [TaskItem] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var showContent = false

    // Modal editing state
    @State private var editingTitle: String = ""
    @State private var editingDescription: String = ""
    @State private var showModalPriorityPicker = false
    @State private var showModalProjectPicker = false
    @State private var allProjects: [Project] = [] // for project picker in modal
    @State private var frozenSourceFrame: CGRect = .zero // captured at expand time
    @State private var showSnackbar = false
    @State private var snackbarMessage = ""
    @State private var snackbarIsSuccess = false
    @State private var newItemIds: Set<UUID> = []
    @State private var keyboardHeight: CGFloat = 0

    private var highTasks: Binding<[TaskItem]> { $highTasks_ }
    private var mediumTasks: Binding<[TaskItem]> { $mediumTasks_ }
    private var lowTasks: Binding<[TaskItem]> { $lowTasks_ }
    private var completedTasks: Binding<[TaskItem]> { $completedTasks_ }

    var body: some View {
        ZStack(alignment: .bottom) {
            bgColor.ignoresSafeArea()

            // Scroll content — blurred by modal, filter, and recording
            ScrollView {
                VStack(spacing: 0) {
                    headerTabs
                        .padding(.top, 8)

                    // Project rail — All tab only, hidden when drilled into a project
                    if selectedTab == "All" && focusedProject == nil && !railProjects.isEmpty {
                        ProjectRail(
                            projects: railProjects,
                            itemCounts: railItemCounts,
                            onSelect: { project in
                                enterProjectDetail(project)
                            },
                            onReorder: { newOrder in
                                ProjectOrder.save(newOrder.map(\.name))
                                // Nudge the view to recompute railProjects.
                                projectOrderRev &+= 1
                            }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { railFrame = geo.frame(in: .global) }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        railFrame = newFrame
                                    }
                            }
                        )
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if selectedTab != "Completed" {
                        filterPills
                    }

                    ZStack {
                        if isLoading {
                            loadingPlaceholder
                                .transition(.opacity)
                        }

                        if selectedTab == "Completed" {
                            // Completed tasks list
                            completedSection
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 20)
                        } else if activeTasksEmpty {
                            // Empty state for All / Today
                            activeEmptyState
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 20)
                        } else if showChronological && selectedTab == "All" {
                            // Chronological flat list
                            chronologicalSection
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTab)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPriorities)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedProjects)
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : 20)
                        } else {
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
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                .background(
                    ScrollViewGestureManager(
                        rowFrames: rowFrames,
                        railFrame: railFrame,
                        reorderTaskId: $reorderTaskId,
                        reorderTranslation: $reorderTranslation,
                        reorderSwapOffset: $reorderSwapOffset,
                        swipeOffsets: $swipeOffsets,
                        onReorderCheck: { taskId in
                            checkDragPosition(taskId: taskId)
                        },
                        onSwipeCommit: { taskId, offset in
                            handleSwipeEnd(taskId: taskId, offset: offset)
                        },
                        onTabSwipe: { tx in
                            // Don't swap tabs while inside a project detail view
                            guard focusedProject == nil else { return }
                            let tabs = ["All", "Today", "Completed"]
                            guard let idx = tabs.firstIndex(of: selectedTab) else { return }
                            if tx < 0, idx < tabs.count - 1 {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedTab = tabs[idx + 1]
                                }
                            } else if tx > 0, idx > 0 {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedTab = tabs[idx - 1]
                                }
                            }
                        }
                    )
                )
            }
            .refreshable {
                // Refresh projects first so any renames in Notion surface
                // before actions (which carry the resolved project name).
                await loadProjects()
                await loadActions()
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
            .blur(radius: isModalExpanded || isFilterExpanded || showCloseButton ? 8 : 0)
            .allowsHitTesting(!(isModalExpanded || isFilterExpanded || showCloseButton))

            // Tap-to-cancel scrim when recording
            if showCloseButton {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.cancelTranscription()
                    }
                    .ignoresSafeArea()
            }

            // Live transcript — shown while recording
            if showCloseButton {
                VStack {
                    Spacer()
                    ScrollView {
                        Text(viewModel.liveTranscript.isEmpty ? "Listening..." : viewModel.liveTranscript)
                            .font(.system(size: 24, weight: .medium))
                            .lineSpacing(38 - 24) // 38px line height
                            .foregroundStyle(viewModel.liveTranscript.isEmpty ? textColor.opacity(0.3) : textColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: 200)
                    .padding(.bottom, 220)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.liveTranscript)
            }

            // Button — always on top, fades out for modal/filter overlays
            makeANoteButton
                .padding(.bottom, 16)
                .opacity(isModalExpanded || isFilterExpanded || showTypedNoteModal ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: isModalExpanded)
                .animation(.easeInOut(duration: 0.25), value: isFilterExpanded)
                .animation(.easeInOut(duration: 0.25), value: showTypedNoteModal)
        }
        .overlay {
            if let expandedId = expandedTaskId, let task = findTask(by: expandedId) {
                taskModalOverlay(task: task, sourceFrame: frozenSourceFrame)
            }
        }
        .overlay {
            filterModalOverlay
        }
        .overlay {
            if showTypedNoteModal {
                typedNoteOverlay
            }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            if let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                keyboardHeight = 0
            }
        }
        .onChange(of: viewModel.state) { oldState, newState in
            if newState == .submitting && oldState == .clarification {
                // Re-submitting after project pick — show processing snackbar
                snackbarIsSuccess = false
                snackbarMessage = "Processing"
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSnackbar = true
                }
            } else if newState == .success {
                // Capture values before reset clears them
                let actions = viewModel.actions
                let project = viewModel.matchedProject
                let count = actions.count

                appendCapturedActions(actions: actions, project: project)
                viewModel.reset()

                snackbarMessage = "\(count) action\(count == 1 ? "" : "s") added"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    snackbarIsSuccess = true
                    showSnackbar = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSnackbar = false
                    }
                    // Reset for next use
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        snackbarIsSuccess = false
                    }
                }
            } else if newState == .error {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.easeOut(duration: 0.3)) {
                    showSnackbar = false
                }
            } else if newState == .idle && showSnackbar && !snackbarIsSuccess {
                // Cancelled
                withAnimation(.easeOut(duration: 0.3)) {
                    showSnackbar = false
                }
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
            var completed: [TaskItem] = []

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            for (index, action) in actions.enumerated() {
                let item = TaskItem(
                    notionId: action.id,
                    title: action.title,
                    isCompleted: action.status == "Done",
                    description: (action.description ?? "").isEmpty ? nil : action.description,
                    priority: action.priority.capitalized,
                    projectName: action.projectName.isEmpty ? nil : action.projectName,
                    projectId: (action.projectId ?? "").isEmpty ? nil : action.projectId,
                    createdAt: isoFormatter.date(from: action.createdAt),
                    taskId: action.taskId
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

                if action.status == "Done" {
                    completed.append(item)
                } else {
                    switch action.priority.lowercased() {
                    case "high": high.append(item)
                    case "low": low.append(item)
                    default: medium.append(item)
                    }
                }
            }

            // Today only contains actions the user has manually pinned via
            // the "+" button on the task modal — no auto-ranking.
            let pinnedNotionIds = TodayPins.load()
            let pinnedLocalIds = allItems
                .filter { !$0.0.isCompleted }
                .compactMap { pair -> UUID? in
                    guard let nid = pair.0.notionId, pinnedNotionIds.contains(nid) else { return nil }
                    return pair.0.id
                }
            let todayIds = Set(pinnedLocalIds)

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
            completedTasks_ = completed
        } catch {
            print("Failed to load actions: \(error)")
        }
    }

    private func loadProjects() async {
        do {
            allProjects = try await api.getProjects()
            viewModel.availableProjectNames = allProjects.map(\.name)
            ProjectColor.seedAssignments(names: allProjects.map(\.name))
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    private func appendCapturedActions(actions: [Action], project: String) {
        var addedIds: [UUID] = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for action in actions {
                let item = TaskItem(
                    notionId: action.notionId,
                    title: action.title,
                    priority: action.priority.capitalized,
                    projectName: project.isEmpty ? nil : project,
                    isToday: false,
                    createdAt: Date()
                )
                addedIds.append(item.id)
                switch action.priority.lowercased() {
                case "high": highTasks_.insert(item, at: 0)
                case "low": lowTasks_.insert(item, at: 0)
                default: mediumTasks_.insert(item, at: 0)
                }
            }
            newItemIds.formUnion(addedIds)
        }
        // Clear new indicators after user has had time to find them
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                newItemIds.subtract(addedIds)
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
        Group {
            if let project = focusedProject {
                // Project detail header — back button + project name
                HStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        exitProjectDetail()
                    } label: {
                        Image("icon_back")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(textColor)
                            .frame(width: 32, height: 32)
                            .frame(width: 43, height: 43)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Text(project.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                HStack(spacing: 20) {
                    tabLabel("All")
                    tabLabel("Today")
                    tabLabel("Completed")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Project Detail Navigation

    private func enterProjectDetail(_ project: Project) {
        previousProjectFilter = selectedProjects
        withAnimation(.easeInOut(duration: 0.3)) {
            focusedProject = project
            selectedProjects = [project.name]
            // Rail lives on All — stay on All when drilling in so the item
            // count on the card matches what the user sees inside.
            if selectedTab != "All" { selectedTab = "All" }
        }
    }

    private func exitProjectDetail() {
        withAnimation(.easeInOut(duration: 0.3)) {
            focusedProject = nil
            selectedProjects = previousProjectFilter
        }
        previousProjectFilter = []
    }

    /// Active color theme for primary buttons — nil on Today/All/Completed,
    /// set when drilled into a project detail page.
    private var activeProjectColor: ProjectColor? {
        focusedProject.map { ProjectColor.for(name: $0.name) }
    }

    /// Projects to show in the All-tab rail — derived from the projects that
    /// currently have any active (non-completed) task visible on the All tab.
    /// Order respects the user's persisted drag-to-reorder preference; new
    /// projects fall in alphabetically (the order `apply` sees them in).
    private var railProjects: [Project] {
        // Read projectOrderRev so SwiftUI re-evaluates this after a reorder.
        _ = projectOrderRev
        let names = Set(railItemCounts.keys)
        let visible = allProjects
            .filter { names.contains($0.name) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        let orderedNames = ProjectOrder.apply(to: visible.map(\.name))
        let byName = Dictionary(uniqueKeysWithValues: visible.map { ($0.name, $0) })
        return orderedNames.compactMap { byName[$0] }
    }

    /// Per-project item counts that exactly match what the user will see
    /// inside the project detail view — same predicate as `filteredTasks`,
    /// minus the project filter itself. Any priority filters the user has
    /// active are honored so card counts stay truthful.
    private var railItemCounts: [String: Int] {
        var counts: [String: Int] = [:]
        let all = highTasks_ + mediumTasks_ + lowTasks_
        for t in all where !t.isCompleted {
            // Match filteredTasks() exactly, except ignore the project filter
            // (the card IS the project filter).
            let matchesTab = selectedTab == "All" || t.isToday
            guard matchesTab else { continue }
            // Respect priority filter when active
            if !selectedPriorities.isEmpty && !selectedPriorities.contains(t.priority) {
                continue
            }
            if let name = t.projectName, !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    private func tabLabel(_ label: String) -> some View {
        let isSelected = selectedTab == label
        return Text(label)
            .font(.system(size: isSelected ? 32 : 24, weight: .bold))
            .foregroundStyle(textColor)
            .opacity(isSelected ? 1 : 0.4)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(.interpolate)
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = label
                }
            }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        HStack(spacing: 12) {
            priorityPill {
                tempPriorities = selectedPriorities
                showPriorityFilter = true
                isFilterExpanded = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isFilterExpanded = true
                    }
                }
            }

            // Project pill hidden when drilled into a single project —
            // filtering is already scoped by the focused project.
            if focusedProject == nil {
                projectPill {
                    tempProjects = selectedProjects
                    showProjectFilter = true
                    isFilterExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isFilterExpanded = true
                        }
                    }
                }
            }
            Spacer()

            // Sort toggle — only on All tab
            if selectedTab == "All" {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showChronological.toggle()
                    }
                } label: {
                    Image(systemName: showChronological ? "clock.fill" : "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(showChronological ? .white : pillText)
                        .frame(width: 34, height: 34)
                        .background(showChronological ? pillText : pillBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    private func priorityPill(action: @escaping () -> Void) -> some View {
        let isActive = !selectedPriorities.isEmpty
        let sorted = selectedPriorities.sorted { ["High", "Medium", "Low"].firstIndex(of: $0) ?? 0 < ["High", "Medium", "Low"].firstIndex(of: $1) ?? 0 }
        return Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    HStack(spacing: -4) {
                        ForEach(Array(sorted.enumerated()), id: \.element) { index, priority in
                            Circle()
                                .fill(priorityColor(for: priority))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(isActive ? pillText : pillBg, lineWidth: 1.5)
                                )
                                .zIndex(Double(index))
                        }
                    }
                    Text(sorted.joined(separator: ", "))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Priority")
                        .font(.system(size: 14, weight: .semibold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : pillText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? pillText : pillBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func projectPill(action: @escaping () -> Void) -> some View {
        let isActive = !selectedProjects.isEmpty
        let sorted = selectedProjects.sorted()
        return Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    HStack(spacing: -4) {
                        ForEach(Array(sorted.enumerated()), id: \.element) { index, project in
                            ZStack {
                                Circle()
                                    .fill(avatarColor(for: project))
                                    .frame(width: 18, height: 18)
                                Text(String(project.prefix(1)).uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(isActive ? pillText : pillBg, lineWidth: 1.5)
                            )
                            .zIndex(Double(index))
                        }
                    }
                    Text(sorted.joined(separator: ", "))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Project")
                        .font(.system(size: 14, weight: .semibold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : pillText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? pillText : pillBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Priority Section

    private func prioritySection(label: String, color: Color, tasks: Binding<[TaskItem]>) -> some View {
        let filtered = filteredTasks(tasks)
        let isCollapsed = collapsedSections.contains(label)
        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if isCollapsed {
                                collapsedSections.remove(label)
                            } else {
                                collapsedSections.insert(label)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 12, height: 12)

                            Text(label)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(textColor)

                            Text("\(filtered.count)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(textColor.opacity(0.4))

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(textColor.opacity(0.4))
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label) priority, \(filtered.count) items, \(isCollapsed ? "collapsed" : "expanded")")
                    .accessibilityHint("Double tap to \(isCollapsed ? "expand" : "collapse")")

                    if !isCollapsed {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.1.id) { filteredIndex, item in
                                let (originalIndex, _) = item
                                let isFirst = filteredIndex == 0
                                let isLast = filteredIndex == filtered.count - 1

                                taskRow(tasks: tasks, index: originalIndex, isFirst: isFirst, isLast: isLast)
                                    .zIndex(reorderTaskId == tasks.wrappedValue[originalIndex].id ? 100 : 0)
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 4)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func taskRow(tasks: Binding<[TaskItem]>, index: Int, isFirst: Bool, isLast: Bool) -> some View {
        let task = tasks.wrappedValue[index]
        let offset = swipeOffsets[task.id] ?? 0

        let rowContent = VStack(spacing: 0) {
            HStack(spacing: 15) {
                Button {
                    playCheckboxHaptic()
                    let wasCompleted = tasks.wrappedValue[index].isCompleted
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
                    if !wasCompleted {
                        let taskId = updated.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            moveToCompleted(id: taskId, from: tasks)
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

                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                    .strikethrough(task.isCompleted, color: textColor.opacity(0.3))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        expandTask(task.id)
                    }

                if newItemIds.contains(task.id) {
                    Circle()
                        .fill(Color(red: 0.298, green: 0.761, blue: 0.431))
                        .frame(width: 8, height: 8)
                        .transition(.scale.combined(with: .opacity))
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

        return rowContent
            .hidden()
            .overlay {
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
                rowContent
                    .background(Color.white)
                    .offset(x: offset)
            }
            .clipped()
            .contentShape(Rectangle())
        // Visual feedback for reorder (state driven by UIKit gesture manager)
        .offset(y: reorderTaskId == task.id ? reorderTranslation + reorderSwapOffset : 0)
        .shadow(
            color: reorderTaskId == task.id ? .black.opacity(0.15) : .clear,
            radius: reorderTaskId == task.id ? 12 : 0,
            x: 0, y: 4
        )
        .scaleEffect(reorderTaskId == task.id ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: reorderTaskId)
        // During active drag, suppress layout animations on the dragged item
        // so it stays pinned under the finger (offset handles all positioning).
        // Non-dragged items still animate via withAnimation in checkDragPosition.
        .transaction { t in
            if reorderTaskId == task.id && reorderTranslation != 0 {
                t.animation = nil
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrames[task.id] = geo.frame(in: .global) }
                    .onDisappear { rowFrames.removeValue(forKey: task.id) }
                    .onChange(of: geo.frame(in: .global)) { oldFrame, newFrame in
                        rowFrames[task.id] = newFrame
                        // After a cross-section move, the layout reflows in ways the
                        // manual offset prediction can't anticipate (section gaps, headers).
                        // Auto-correct once, then clear the flag.
                        if reorderTaskId == task.id && pendingCrossSectionCorrection {
                            let delta = newFrame.midY - oldFrame.midY
                            if abs(delta) > 1 {
                                reorderSwapOffset -= delta
                                pendingCrossSectionCorrection = false
                            }
                        }
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
        frozenSourceFrame = rowFrames[id] ?? .zero
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

        // Dismiss keyboard smoothly before collapsing
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Small delay lets the keyboard animate down alongside the card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isModalExpanded = false
            }
            // Wait for spring to fully settle before removing overlay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expandedTaskId = nil
            }
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

    // MARK: - Drag Reorder

    private func bindingForTask(_ taskId: UUID) -> Binding<[TaskItem]>? {
        if highTasks_.contains(where: { $0.id == taskId }) { return highTasks }
        if mediumTasks_.contains(where: { $0.id == taskId }) { return mediumTasks }
        if lowTasks_.contains(where: { $0.id == taskId }) { return lowTasks }
        return nil
    }

    private func priorityForTask(_ taskId: UUID) -> String? {
        if highTasks_.contains(where: { $0.id == taskId }) { return "High" }
        if mediumTasks_.contains(where: { $0.id == taskId }) { return "Medium" }
        if lowTasks_.contains(where: { $0.id == taskId }) { return "Low" }
        return nil
    }

    /// Computed drag offset = gesture translation + accumulated swap adjustments
    private var totalDragTranslation: CGFloat {
        reorderTranslation + reorderSwapOffset
    }

    private func checkDragPosition(taskId: UUID) {
        guard Date().timeIntervalSince(lastSwapTime) > 0.35 else { return }
        guard let currentFrame = rowFrames[taskId] else { return }
        guard let tasks = bindingForTask(taskId) else { return }
        guard let currentIdx = tasks.wrappedValue.firstIndex(where: { $0.id == taskId }) else { return }

        let draggedCenter = currentFrame.midY + totalDragTranslation

        // 1. Try within-section reorder first
        // Check swap with item above
        if currentIdx > 0 {
            let aboveId = tasks.wrappedValue[currentIdx - 1].id
            if let aboveFrame = rowFrames[aboveId], draggedCenter < aboveFrame.midY {
                let distance = currentFrame.midY - aboveFrame.midY
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tasks.wrappedValue.swapAt(currentIdx, currentIdx - 1)
                }
                reorderSwapOffset += distance
                lastSwapTime = Date()
                UISelectionFeedbackGenerator().selectionChanged()
                return
            }
        }

        // Check swap with item below
        if currentIdx < tasks.wrappedValue.count - 1 {
            let belowId = tasks.wrappedValue[currentIdx + 1].id
            if let belowFrame = rowFrames[belowId], draggedCenter > belowFrame.midY {
                let distance = belowFrame.midY - currentFrame.midY
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tasks.wrappedValue.swapAt(currentIdx, currentIdx + 1)
                }
                reorderSwapOffset -= distance
                lastSwapTime = Date()
                UISelectionFeedbackGenerator().selectionChanged()
                return
            }
        }

        // 2. Check cross-section move — if dragged past the edge of current section
        guard let currentPriority = priorityForTask(taskId) else { return }

        let sectionOrder: [(String, Binding<[TaskItem]>)] = [
            ("High", highTasks),
            ("Medium", mediumTasks),
            ("Low", lowTasks)
        ]

        // Find the closest item in adjacent sections
        for (priority, binding) in sectionOrder {
            if priority == currentPriority { continue }
            let items = binding.wrappedValue
            guard !items.isEmpty else { continue }

            // Check if dragged center is within this section's row area
            let frames = items.compactMap { rowFrames[$0.id] }
            guard let sectionMinY = frames.map(\.minY).min(),
                  let sectionMaxY = frames.map(\.maxY).max() else { continue }

            if draggedCenter >= sectionMinY - 30 && draggedCenter <= sectionMaxY + 30 {
                // Find closest row in target section
                var closestIdx = 0
                var closestDist = CGFloat.infinity
                for (i, item) in items.enumerated() {
                    if let frame = rowFrames[item.id] {
                        let dist = abs(draggedCenter - frame.midY)
                        if dist < closestDist {
                            closestDist = dist
                            closestIdx = i
                        }
                    }
                }

                // Calculate target position for translation adjustment
                let targetFrame = rowFrames[items[closestIdx].id]
                let targetMidY = targetFrame?.midY ?? currentFrame.midY
                let distance = targetMidY - currentFrame.midY

                // Remove from current section
                guard let idx = tasks.wrappedValue.firstIndex(where: { $0.id == taskId }) else { return }
                var task = tasks.wrappedValue[idx]
                task.priority = priority

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tasks.wrappedValue.remove(at: idx)

                    // Insert into target section at the closest position
                    let insertIdx = draggedCenter < (targetFrame?.midY ?? 0) ? closestIdx : min(closestIdx + 1, items.count)
                    binding.wrappedValue.insert(task, at: insertIdx)
                }

                // Adjust translation so the row stays under the finger.
                // The manual prediction handles the row-to-row distance, but can't
                // account for section gaps/headers. The GeometryReader will auto-correct
                // the remainder on the next layout pass.
                reorderSwapOffset -= distance
                pendingCrossSectionCorrection = true
                lastSwapTime = Date()
                playCheckboxHaptic()

                // Sync to Notion
                if let notionId = task.notionId {
                    Task {
                        try? await api.updateAction(id: notionId, fields: ["priority": priority.lowercased()])
                    }
                }
                return
            }
        }
    }

    @discardableResult
    private func moveTaskToPriority(id: UUID, newPriority: String) -> Bool {
        // Check if already in the target priority
        let targetBinding: Binding<[TaskItem]> = {
            switch newPriority {
            case "High": return highTasks
            case "Low": return lowTasks
            default: return mediumTasks
            }
        }()
        if targetBinding.wrappedValue.contains(where: { $0.id == id }) { return false }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            updateTaskPriority(id: id, newPriority: newPriority)
        }
        playCheckboxHaptic()
        return true
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

    /// Flips whether `task` appears in the Today tab. Persists via `TodayPins`
    /// so the override survives reloads, and mutates local state so the modal
    /// reflects the new value immediately.
    private func togglePinToToday(id: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                guard let notionId = binding.wrappedValue[idx].notionId else { return }
                let isNowPinned = TodayPins.toggle(notionId)
                withAnimation(.easeInOut(duration: 0.18)) {
                    binding.wrappedValue[idx].isToday = isNowPinned
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
        }
    }

    // MARK: - Chronological View

    private func bindingAndIndex(for taskId: UUID) -> (Binding<[TaskItem]>, Int)? {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == taskId }) {
                return (binding, idx)
            }
        }
        return nil
    }

    private var chronologicalTasks: [TaskItem] {
        let all = highTasks.wrappedValue + mediumTasks.wrappedValue + lowTasks.wrappedValue
        return all
            .filter { task in
                let matchesTab = selectedTab == "All" || task.isToday
                let matchesProject = selectedProjects.isEmpty || selectedProjects.contains(task.projectName ?? "")
                let matchesPriority = selectedPriorities.isEmpty || selectedPriorities.contains(task.priority)
                return matchesTab && matchesProject && matchesPriority && !task.isCompleted
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private func chronologicalLabel(for date: Date?) -> String {
        guard let date else { return "Older" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return "This Week"
        }
        return "Older"
    }

    private var chronologicalSection: some View {
        let tasks = chronologicalTasks
        let grouped: [(String, [TaskItem])] = {
            let order = ["Today", "Yesterday", "This Week", "Older"]
            var dict: [String: [TaskItem]] = [:]
            for task in tasks {
                let label = chronologicalLabel(for: task.createdAt)
                dict[label, default: []].append(task)
            }
            return order.compactMap { key in
                guard let items = dict[key], !items.isEmpty else { return nil }
                return (key, items)
            }
        }()

        return VStack(spacing: 32) {
            ForEach(grouped, id: \.0) { label, items in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.5))

                        Text(label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(textColor)

                        Text("\(items.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.4))
                    }
                    .padding(.vertical, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, task in
                            if let (binding, originalIndex) = bindingAndIndex(for: task.id) {
                                taskRow(
                                    tasks: binding,
                                    index: originalIndex,
                                    isFirst: idx == 0,
                                    isLast: idx == items.count - 1
                                )
                                .zIndex(reorderTaskId == task.id ? 100 : 0)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 4)
                }
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
            return matchesTab && matchesProject && !task.isCompleted
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

    private var activeTasksEmpty: Bool {
        filteredTasks(highTasks).isEmpty
        && filteredTasks(mediumTasks).isEmpty
        && filteredTasks(lowTasks).isEmpty
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

    private func moveToCompleted(id: UUID, from tasks: Binding<[TaskItem]>) {
        guard let idx = tasks.wrappedValue.firstIndex(where: { $0.id == id && $0.isCompleted }) else { return }
        let task = tasks.wrappedValue[idx]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tasks.wrappedValue.remove(at: idx)
            completedTasks_.insert(task, at: 0)
        }
    }

    private func moveFromCompleted(id: UUID) {
        guard let idx = completedTasks_.firstIndex(where: { $0.id == id }) else { return }
        var task = completedTasks_[idx]
        task.isCompleted = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            completedTasks_.remove(at: idx)
            switch task.priority {
            case "High": highTasks_.append(task)
            case "Low": lowTasks_.append(task)
            default: mediumTasks_.append(task)
            }
        }
        if let notionId = task.notionId {
            Task {
                try? await api.updateActionStatus(id: notionId, status: "To Do")
            }
        }
    }

    /// Unified swipe handler called by UIKit gesture manager for both active and completed rows.
    private func handleSwipeEnd(taskId: UUID, offset: CGFloat) {
        let threshold: CGFloat = 80

        if offset < -threshold {
            // Swipe left → complete (active) or uncomplete (completed)
            if completedTasks_.contains(where: { $0.id == taskId }) {
                playCheckboxHaptic()
                moveFromCompleted(id: taskId)
            } else {
                playCheckboxHaptic()
                completeTaskById(taskId)
            }
        } else if offset > threshold {
            // Swipe right → delete (wide swipe = instant, short swipe = confirm)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let instantDeleteThreshold: CGFloat = 200
            if offset > instantDeleteThreshold {
                swipeOffsets[taskId] = 0
                deleteTask(id: taskId)
                rowFrames.removeValue(forKey: taskId)
                return
            } else {
                deleteTargetId = taskId
                showDeleteConfirm = true
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            swipeOffsets[taskId] = 0
        }
    }

    /// Marks a task complete by ID (used by swipe gesture manager).
    private func completeTaskById(_ taskId: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == taskId }) {
                withAnimation(.easeInOut(duration: 0.12)) {
                    binding.wrappedValue[idx].isCompleted = true
                }
                let task = binding.wrappedValue[idx]
                if let notionId = task.notionId {
                    Task {
                        try? await api.updateActionStatus(id: notionId, status: "Done")
                    }
                }
                let id = task.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.moveToCompleted(id: id, from: binding)
                }
                return
            }
        }
    }

    private var activeEmptyState: some View {
        let isFiltered = !selectedPriorities.isEmpty || !selectedProjects.isEmpty
        let isToday = selectedTab == "Today"

        return VStack(spacing: 16) {
            Image(systemName: isToday ? "sun.max" : (isFiltered ? "line.3.horizontal.decrease" : "tray"))
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(textColor.opacity(0.2))

            Text(isToday ? "Nothing for today" : (isFiltered ? "No matching actions" : "No actions yet"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(textColor.opacity(0.3))

            Text(isToday ? "Your highest-priority actions will appear here" : (isFiltered ? "Try adjusting your filters" : "Tap \"Add note\" to get started"))
                .font(.system(size: 14))
                .foregroundStyle(textColor.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(textColor.opacity(0.06), lineWidth: 4)
        )
    }

    private var completedSection: some View {
        Group {
            if completedTasks_.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(textColor.opacity(0.2))

                    Text("No completed items")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(textColor.opacity(0.06), lineWidth: 4)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(completedTasks_.enumerated()), id: \.element.id) { index, task in
                        let isFirst = index == 0
                        let isLast = index == completedTasks_.count - 1
                        completedRow(task: task, isFirst: isFirst, isLast: isLast)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 4)
            }
        }
    }

    private func completedRow(task: TaskItem, isFirst: Bool, isLast: Bool) -> some View {
        let offset = swipeOffsets[task.id] ?? 0

        let rowContent = VStack(spacing: 0) {
            HStack(spacing: 15) {
                Button {
                    playCheckboxHaptic()
                    moveFromCompleted(id: task.id)
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(completedBg)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(completedCheck)
                        )
                }
                .buttonStyle(.plain)
                .padding(18)
                .contentShape(Rectangle())
                .padding(-18)

                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.4))
                    .strikethrough(true, color: textColor.opacity(0.3))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)

            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
            }
        }

        return rowContent
            .hidden()
            .overlay {
                ZStack {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.918, green: 0.306, blue: 0.306))
                    .opacity(offset > 0 ? 1 : 0)

                    HStack {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.298, green: 0.761, blue: 0.431))
                    .opacity(offset < 0 ? 1 : 0)
                }
            }
            .overlay {
                rowContent
                    .background(Color.white)
                    .offset(x: offset)
            }
            .clipped()
            .contentShape(Rectangle())
            // Swipe handled by UIKit gesture manager — register frame for hit testing
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { rowFrames[task.id] = geo.frame(in: .global) }
                        .onDisappear { rowFrames.removeValue(forKey: task.id) }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            rowFrames[task.id] = newFrame
                        }
                }
            )
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
        if let task = completedTasks_.first(where: { $0.id == id }) {
            return task
        }
        return nil
    }

    private func toggleTask(id: UUID) {
        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                let wasCompleted = binding.wrappedValue[idx].isCompleted
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
                if !wasCompleted {
                    let taskId = updated.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        moveToCompleted(id: taskId, from: binding)
                    }
                }
                return
            }
        }
    }

    private func deleteTask(id: UUID) {
        // Clean up gesture state
        swipeOffsets.removeValue(forKey: id)
        rowFrames.removeValue(forKey: id)

        for binding in [highTasks, mediumTasks, lowTasks] {
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == id }) {
                let task = binding.wrappedValue[idx]
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    binding.wrappedValue.remove(at: idx)
                }
                if let notionId = task.notionId {
                    Task {
                        do {
                            try await api.updateActionStatus(id: notionId, status: "Archived")
                            print("[Noteee] Archived task \(notionId)")
                        } catch {
                            print("[Noteee] ERROR archiving task \(notionId): \(error)")
                        }
                    }
                } else {
                    print("[Noteee] WARNING: task has no notionId, cannot archive")
                }
                deleteTargetId = nil
                return
            }
        }
        // Also check completed tasks
        if let idx = completedTasks_.firstIndex(where: { $0.id == id }) {
            let task = completedTasks_[idx]
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                completedTasks_.remove(at: idx)
            }
            if let notionId = task.notionId {
                Task {
                    do {
                        try await api.updateActionStatus(id: notionId, status: "Archived")
                        print("[Noteee] Archived completed task \(notionId)")
                    } catch {
                        print("[Noteee] ERROR archiving completed task \(notionId): \(error)")
                    }
                }
            } else {
                print("[Noteee] WARNING: completed task has no notionId, cannot archive")
            }
            deleteTargetId = nil
        }
    }

    private func priorityColor(for priority: String) -> Color {
        switch priority {
        case "High": return highColor
        case "Low": return lowColor
        default: return mediumColor
        }
    }

    /// Single source of truth for project avatar colors — delegates to the
    /// shared `ProjectColor` palette so rail cards, clarification sheet,
    /// and task-edit modal all render identically for a given project.
    private func avatarColor(for name: String) -> Color {
        ProjectColor.for(name: name).base
    }

    @ViewBuilder
    private func taskModalOverlay(task: TaskItem, sourceFrame: CGRect) -> some View {
        GeometryReader { geo in
            let screenSize = geo.size
            let safeArea = geo.safeAreaInsets

            let collapsedY = sourceFrame.minY - safeArea.top
            let availableHeight = screenSize.height - keyboardHeight
            let expandedY = (availableHeight - 310) / 2

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

                        TextField("Title", text: $editingTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(task.isCompleted ? textColor.opacity(0.4) : textColor)
                            .lineLimit(1...3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .disabled(!isModalExpanded)
                            .submitLabel(.done)
                            .onChange(of: editingTitle) { _, newValue in
                                // Vertical-axis TextField inserts \n on return instead of firing onSubmit.
                                // Intercept, strip the newline, and submit.
                                if newValue.contains("\n") {
                                    editingTitle = newValue.replacingOccurrences(of: "\n", with: "")
                                    collapseModal()
                                }
                            }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)

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

                            TextField("", text: $editingDescription, prompt: Text("Add a description...").foregroundStyle(descriptionLabel), axis: .vertical)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(textColor)
                                .lineLimit(3...5)
                                .submitLabel(.done)
                                .onChange(of: editingDescription) { _, newValue in
                                    if newValue.contains("\n") {
                                        editingDescription = newValue.replacingOccurrences(of: "\n", with: "")
                                        collapseModal()
                                    }
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

                            // Project — tappable to change, fills remaining space
                            Button {
                                showModalProjectPicker.toggle()
                                showModalPriorityPicker = false
                            } label: {
                                HStack(spacing: 8) {
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
                                            .lineLimit(1)
                                            .truncationMode(.tail)
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

                            Spacer(minLength: 0)

                            // Add-to-Today toggle — pins the action to the
                            // Today tab regardless of auto-ranking. Filled
                            // state means it's currently pinned.
                            Button {
                                togglePinToToday(id: task.id)
                            } label: {
                                Image(systemName: task.isToday ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(task.isToday ? primaryBlue : descriptionLabel)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.isToday ? "Remove from Today" : "Add to Today")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)

                        // Task ID label
                        if let taskId = task.taskId {
                            Rectangle()
                                .fill(Color.black.opacity(0.1))
                                .frame(height: 1)

                            HStack {
                                Text(taskId)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(descriptionLabel)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                        }

                        // Inline priority picker
                        VStack(spacing: 0) {
                            if showModalPriorityPicker {
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
                        }
                        .clipped()

                        // Inline project picker
                        VStack(spacing: 0) {
                            if showModalProjectPicker {
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
                        }
                        .clipped()
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
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: keyboardHeight)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showModalPriorityPicker)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showModalProjectPicker)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Typed Note Modal

    private var typedNoteOverlay: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            let topPad: CGFloat = typedNoteDescriptionFocused ? safeArea.top + 20 : 160
            let bottomStop = keyboardHeight > 0 ? keyboardHeight : safeArea.bottom
            let availableHeight = geo.size.height - topPad - bottomStop - 20

            ZStack(alignment: .top) {
                // Scrim — tap to dismiss
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture { dismissTypedNote() }

                // Card with heading + description
                VStack(alignment: .leading, spacing: 0) {
                    // Heading field
                    TextField("", text: $typedNoteText, prompt: Text("Heading").foregroundStyle(descriptionLabel), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(1...3)
                        .focused($typedNoteFocused)
                        .submitLabel(.next)
                        .onChange(of: typedNoteText) { _, newValue in
                            if newValue.contains("\n") {
                                typedNoteText = newValue.replacingOccurrences(of: "\n", with: "")
                                typedNoteDescriptionFocused = true
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 1)

                    // Description field — scrollable, fills remaining space
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Description")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(descriptionLabel)

                            TextField("", text: $typedNoteDescription, prompt: Text("Add a description...").foregroundStyle(descriptionLabel), axis: .vertical)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(textColor)
                                .lineLimit(3...)
                                .focused($typedNoteDescriptionFocused)
                                .submitLabel(.send)
                                .onChange(of: typedNoteDescription) { _, newValue in
                                    if newValue.contains("\n") {
                                        typedNoteDescription = newValue.replacingOccurrences(of: "\n", with: "")
                                        submitTypedNote()
                                    }
                                }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                    }
                }
                .frame(maxHeight: typedNoteDescriptionFocused ? availableHeight : nil)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 4)
                .padding(.horizontal, 24)
                .padding(.top, topPad)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: typedNoteDescriptionFocused)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardHeight)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showTypedNoteModal)
    }

    private func submitTypedNote() {
        let heading = typedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = typedNoteDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else {
            dismissTypedNote()
            return
        }
        typedNoteFocused = false
        typedNoteDescriptionFocused = false
        let combined = description.isEmpty ? heading : "\(heading). \(description)"
        viewModel.submitTypedNote(combined)
        showTypedNoteModal = false
        typedNoteText = ""
        typedNoteDescription = ""
    }

    private func dismissTypedNote() {
        typedNoteFocused = false
        typedNoteDescriptionFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            showTypedNoteModal = false
        }
        typedNoteText = ""
        typedNoteDescription = ""
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
            .ignoresSafeArea(edges: .bottom)
            .offset(y: isFilterExpanded ? 0 : UIScreen.main.bounds.height)
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
                    .contentShape(Rectangle())
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
                    .background(primaryButtonColor)
                    .clipShape(Capsule())
                    .modifier(ShimmerBorder())
                    .shadow(color: Color(red: 0.184, green: 0.471, blue: 0.647).opacity(0.2), radius: 16, x: 0, y: 4)
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
                    .contentShape(Rectangle())
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
                    .background(primaryButtonColor)
                    .clipShape(Capsule())
                    .modifier(ShimmerBorder())
                    .shadow(color: Color(red: 0.184, green: 0.471, blue: 0.647).opacity(0.2), radius: 16, x: 0, y: 4)
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
    private var isProcessing: Bool { viewModel.state == .submitting }
    private var showCloseButton: Bool { isRecording }

    private var makeANoteButton: some View {
        VStack(spacing: 16) {
            // Snackbar — sits above the button
            if showSnackbar {
                HStack(spacing: 10) {
                    if snackbarIsSuccess {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(snackbarMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(snackbarIsSuccess ? Color(red: 0.298, green: 0.761, blue: 0.431) : textColor)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: snackbarIsSuccess)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: snackbarMessage)
            }

            VStack(spacing: 32) {
                HStack(spacing: 12) {
                // Single button that morphs from capsule to circle
                Button {
                    if showCloseButton {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    viewModel.toggleRecording()
                } label: {
                    let buttonColor = activeProjectColor ?? .defaultBlue
                    ZStack {
                        // Mic icon + text — fixed size, fades out cleanly
                        HStack(spacing: 10) {
                            Image("icon_mic")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(buttonColor.text)

                            Text("Add note")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(buttonColor.text)
                                .fixedSize()
                        }
                        .padding(.horizontal, 24)
                        .opacity(showCloseButton ? 0 : 1)

                        // Checkmark — fades in when recording
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(showCloseButton ? 1 : 0)
                    }
                    .clipped()
                    .frame(
                        width: showCloseButton ? 88 : nil,
                        height: showCloseButton ? 88 : 56
                    )
                    .background {
                        if showCloseButton {
                            Color(red: 0.319, green: 0.743, blue: 0.319)
                        } else {
                            buttonColor.fill
                        }
                    }
                    .clipShape(Capsule())
                    .modifier(ShimmerBorder())
                    .shadow(
                        color: showCloseButton
                            ? Color(red: 0.319, green: 0.743, blue: 0.319).opacity(0.75)
                            : buttonColor.shadow.opacity(0.4),
                        radius: 32,
                        x: 0, y: 4
                    )
                    .shadow(
                        color: showCloseButton
                            ? Color(red: 0.319, green: 0.743, blue: 0.319).opacity(0.5)
                            : buttonColor.shadow.opacity(0.55),
                        radius: 12,
                        x: 0, y: 4
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                    // Secondary: typed-note entry (pencil with square) — right of main button
                    if !showCloseButton {
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            typedNoteText = ""
                            typedNoteDescription = ""
                            showTypedNoteModal = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                typedNoteFocused = true
                            }
                        } label: {
                            let pencilColor = activeProjectColor ?? .defaultBlue
                            Image("icon_edit_square")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .foregroundStyle(pencilColor.text)
                                .frame(width: 56, height: 56)
                                .background { pencilColor.fill }
                                .clipShape(Circle())
                                .shadow(
                                    color: pencilColor.shadow.opacity(0.4),
                                    radius: 32, x: 0, y: 4
                                )
                                .shadow(
                                    color: pencilColor.shadow.opacity(0.55),
                                    radius: 12, x: 0, y: 4
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                        .accessibilityLabel("Type a note")
                        .transition(.opacity.combined(with: .scale))
                    }
                }

                // Cancel — appears below when recording
                if showCloseButton {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.cancelTranscription()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.38))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: showCloseButton)
        .animation(.easeInOut(duration: 0.3), value: isProcessing)
    }
}

#Preview {
    HomeView(viewModel: CaptureViewModel())
}
