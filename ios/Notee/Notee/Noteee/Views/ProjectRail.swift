import SwiftUI
import UIKit

// MARK: - Project Rail
//
// Horizontal, swipeable rail of square project cards shown on the All tab.
// Each card displays the project name and its active (non-completed) item
// count.
//
// Interactions:
//   - Tap → fires `onSelect(project)`.
//   - Long-press (~400ms, finger stationary) → card lifts with a haptic,
//     the rail's scroll is locked, and the finger then drags the card
//     along the horizontal axis. As the card's centre crosses a
//     neighbour's midpoint the order shuffles live. On release the new
//     order is committed via `onReorder`.
//
// Scroll vs reorder arbitration is delegated to UIKit: a
// `UILongPressGestureRecognizer` with `minimumPressDuration = 0.4` and a
// small `allowableMovement` sits on each card. If the finger moves
// sideways before the timer elapses, the long-press fails and the
// enclosing UIScrollView's pan takes over normally. Only a truly
// stationary hold starts the reorder flow.
//
// Ordering is persisted by the caller through `ProjectOrder`.

struct ProjectRail: View {

    let projects: [Project]
    /// Map of project name → active item count, computed by the caller from
    /// the current Home view task state. Projects with zero items still show.
    let itemCounts: [String: Int]
    let onSelect: (Project) -> Void
    let onReorder: ([Project]) -> Void

    /// Local ordered copy — mutated live during a drag so the HStack
    /// visibly shuffles without waiting for the parent to commit. Seeded
    /// from `projects` and re-synced whenever the caller passes a new list.
    @State private var ordered: [Project] = []
    /// Identifier of the card the user is currently dragging, if any.
    @State private var draggingId: String? = nil
    /// Live horizontal offset of the dragging card in points.
    @State private var dragOffset: CGFloat = 0

    /// Card width + inter-card spacing — used to convert drag translation
    /// into a swap distance. Must match the card frame + HStack spacing.
    private let cardWidth: CGFloat = 132
    private let cardSpacing: CGFloat = 14
    private var stepWidth: CGFloat { cardWidth + cardSpacing }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(ordered) { project in
                    ProjectRailCard(
                        project: project,
                        color: ProjectColor.for(name: project.name),
                        itemCount: itemCounts[project.name] ?? 0
                    )
                    .scaleEffect(draggingId == project.id ? 1.05 : 1.0)
                    .shadow(
                        color: .black.opacity(draggingId == project.id ? 0.25 : 0),
                        radius: 20, x: 0, y: 8
                    )
                    .offset(x: draggingId == project.id ? dragOffset : 0)
                    .zIndex(draggingId == project.id ? 1 : 0)
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.82),
                        value: draggingId == nil ? 0 : indexOf(project)
                    )
                    .overlay(
                        LongPressDragRecognizer(
                            onBegan: { handleBegan(project) },
                            onChanged: { translation in handleChanged(project, translation: translation) },
                            onEnded: { handleEnded() },
                            onTap: {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                onSelect(project)
                            }
                        )
                    )
                }
            }
            .padding(.horizontal, 24)
            // Vertical breathing room so card drop shadows aren't clipped by
            // the ScrollView bounds. Resting shadow is radius 12 / y 4, but
            // during a drag the lifted card renders a radius-20 / y-8 shadow
            // at 1.05× scale — padding must accommodate the worst case.
            .padding(.vertical, 32)
        }
        .scrollDisabled(draggingId != nil)
        .onAppear { ordered = projects }
        .onChange(of: projects) { _, newValue in
            // Respect in-flight drags — don't stomp on the user's local
            // reorder mid-gesture.
            if draggingId == nil {
                ordered = newValue
            }
        }
    }

    private func indexOf(_ project: Project) -> Int {
        ordered.firstIndex(where: { $0.id == project.id }) ?? 0
    }

    // MARK: - Gesture callbacks

    private func handleBegan(_ project: Project) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            draggingId = project.id
            dragOffset = 0
        }
    }

    private func handleChanged(_ project: Project, translation: CGPoint) {
        guard draggingId == project.id else { return }
        dragOffset = translation.x
        updateLiveOrder(for: project)
    }

    private func handleEnded() {
        guard draggingId != nil else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            draggingId = nil
            dragOffset = 0
        }
        onReorder(ordered)
    }

    /// Recomputes the dragging card's index based on how far it has travelled
    /// relative to its starting slot, and moves it in `ordered` if it has
    /// crossed a neighbour's midpoint. Runs on every drag update.
    private func updateLiveOrder(for project: Project) {
        guard let currentIndex = ordered.firstIndex(where: { $0.id == project.id }) else { return }
        let steps = Int((dragOffset / stepWidth).rounded())
        guard steps != 0 else { return }

        let target = max(0, min(ordered.count - 1, currentIndex + steps))
        guard target != currentIndex else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            let moved = ordered.remove(at: currentIndex)
            ordered.insert(moved, at: target)
        }
        // Compensate so the card stays visually under the user's finger:
        // each full swap consumes `stepWidth` of the stored offset.
        dragOffset -= CGFloat(target - currentIndex) * stepWidth
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - UIKit gesture bridge
//
// Hosts a UILongPressGestureRecognizer that requires 0.4s of stationary
// holding before firing. Because UIKit's gesture recognizer system knows
// how to arbitrate with the enclosing UIScrollView's pan recognizer, quick
// horizontal swipes scroll the rail normally — the long press simply
// fails when the finger moves more than `allowableMovement` before the
// minimum press duration elapses. A separate tap recognizer is added so
// quick taps still fire `onTap`.

private struct LongPressDragRecognizer: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded, onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        // If the finger moves more than this before the press fires, the
        // gesture fails and the ScrollView's pan kicks in instead.
        longPress.allowableMovement = 12
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        // Let the long press beat the tap when both would fire.
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: () -> Void
        var onTap: () -> Void
        /// Where the finger was when the long-press fired — used so
        /// `onChanged` reports translation relative to lift-off, not
        /// relative to the view origin.
        private var liftOffLocation: CGPoint = .zero

        init(onBegan: @escaping () -> Void,
             onChanged: @escaping (CGPoint) -> Void,
             onEnded: @escaping () -> Void,
             onTap: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onTap = onTap
        }

        @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            switch gr.state {
            case .began:
                // CRITICAL: capture finger position in *window* coordinates,
                // not in the recognizer's view. The card view moves during
                // reorder (both via `.offset` and via HStack slot shuffle),
                // so view-local coordinates jump every time the order
                // changes, causing feedback-loop jank. Window coordinates
                // are invariant to any of that.
                liftOffLocation = gr.location(in: nil)
                // Cache the enclosing scroll view for edge auto-scroll.
                enclosingScrollView = findEnclosingScrollView(from: gr.view)
                onBegan()
            case .changed:
                let now = gr.location(in: nil)
                let dx = now.x - liftOffLocation.x
                let dy = now.y - liftOffLocation.y
                onChanged(CGPoint(x: dx, y: dy))
                updateEdgeAutoScroll(fingerWindowX: now.x)
            case .ended, .cancelled, .failed:
                stopEdgeAutoScroll()
                enclosingScrollView = nil
                onEnded()
            default:
                break
            }
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended else { return }
            onTap()
        }

        // Allow our recognisers to coexist with the enclosing UIScrollView's
        // pan — default UIKit arbitration handles failure/dependency.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return false
        }

        // MARK: - Edge auto-scroll
        //
        // While the user drags a card, the enclosing ScrollView's pan is
        // disabled (see `.scrollDisabled(draggingId != nil)` in the view).
        // But the user still needs a way to scroll to slots that are
        // currently off-screen. We mimic the iOS home-screen behaviour: if
        // the finger hovers within `edgeZone` points of either edge of the
        // screen, we continuously shift `contentOffset` toward that edge at
        // a rate proportional to how deep the finger is into the zone.

        private weak var enclosingScrollView: UIScrollView?
        private var autoScrollLink: CADisplayLink?
        /// Points-per-frame when the finger is fully at the edge.
        private let maxAutoScrollSpeed: CGFloat = 12
        /// Width of the trigger zone at each edge.
        private let edgeZone: CGFloat = 70
        private var currentAutoScrollDelta: CGFloat = 0

        private func findEnclosingScrollView(from view: UIView?) -> UIScrollView? {
            var current: UIView? = view?.superview
            while let v = current {
                if let scroll = v as? UIScrollView { return scroll }
                current = v.superview
            }
            return nil
        }

        private func updateEdgeAutoScroll(fingerWindowX: CGFloat) {
            guard let scroll = enclosingScrollView else { return }
            let screenWidth = UIScreen.main.bounds.width
            let leftDepth = max(0, edgeZone - fingerWindowX)
            let rightDepth = max(0, fingerWindowX - (screenWidth - edgeZone))

            if leftDepth > 0 {
                currentAutoScrollDelta = -(leftDepth / edgeZone) * maxAutoScrollSpeed
            } else if rightDepth > 0 {
                currentAutoScrollDelta = (rightDepth / edgeZone) * maxAutoScrollSpeed
            } else {
                currentAutoScrollDelta = 0
            }

            if currentAutoScrollDelta != 0 {
                startAutoScrollLoopIfNeeded(on: scroll)
            } else {
                stopEdgeAutoScroll()
            }
        }

        private func startAutoScrollLoopIfNeeded(on scroll: UIScrollView) {
            guard autoScrollLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tickAutoScroll))
            link.add(to: .main, forMode: .common)
            autoScrollLink = link
        }

        @objc private func tickAutoScroll() {
            guard let scroll = enclosingScrollView, currentAutoScrollDelta != 0 else {
                stopEdgeAutoScroll()
                return
            }
            let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
            let newX = min(maxX, max(0, scroll.contentOffset.x + currentAutoScrollDelta))
            if newX != scroll.contentOffset.x {
                scroll.contentOffset.x = newX
            }
        }

        private func stopEdgeAutoScroll() {
            autoScrollLink?.invalidate()
            autoScrollLink = nil
            currentAutoScrollDelta = 0
        }
    }
}

/// Transparent hit-testing host — passes touches through to underlying
/// SwiftUI content if our gesture recognisers don't claim them.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // We ourselves accept touches (so our gesture recognisers fire)
        // but only within our bounds.
        return bounds.contains(point) ? self : nil
    }
}

// MARK: - Card

private struct ProjectRailCard: View {

    let project: Project
    let color: ProjectColor
    let itemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text(project.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color.text)
                .lineLimit(1)
            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color.text.opacity(0.75))
        }
        .padding(16)
        .frame(width: 132, height: 132, alignment: .bottomLeading)
        .background { color.fill }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: color.shadow.opacity(0.35), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(itemCount) items")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ProjectRail(
        projects: [
            Project(id: "1", name: "Notee", description: ""),
            Project(id: "2", name: "Deck Table", description: ""),
            Project(id: "3", name: "Personal", description: ""),
            Project(id: "4", name: "Work", description: "")
        ],
        itemCounts: ["Notee": 12, "Deck Table": 8, "Personal": 4, "Work": 2],
        onSelect: { _ in },
        onReorder: { _ in }
    )
    .padding(.vertical, 40)
    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
}
