import SwiftUI
import UIKit

/// A held item moves in the same scroll surface. A quick horizontal gesture
/// remains a swipe; it cannot become a deletion reveal after the item is lifted.
@MainActor final class HomeDrag: ObservableObject {
    static let shared = HomeDrag()
    @Published private(set) var item: String?
    @Published var translation: CGSize = .zero
    @Published private(set) var target: String?
    @Published private(set) var source: String?
    var frames: [String: CGRect] = [:]
    var accept: ((String, Bool) -> Void)?
    func lift(_ id: String) {
        guard item != id else { return }
        item = id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func update(_ value: DragGesture.Value) {
        if source == nil { source = frames.first { $0.value.contains(value.startLocation) }?.key }
        translation = value.translation
        target = frames.first { $0.value.contains(value.location) }?.key
    }
    func finish(at point: CGPoint) {
        let source = item
        let destination = frames.first { $0.value.contains(point) }?.key
        reset()
        if let source, let destination { accept?(source, destination == "routine") }
    }
    func reset() { item = nil; translation = .zero; target = nil; source = nil }
}

struct HomeDropFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct HomeDropArea: ViewModifier {
    let id: String
    @ObservedObject private var drag = HomeDrag.shared
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .background(GeometryReader { proxy in Color.clear.preference(key: HomeDropFrames.self, value: [id: proxy.frame(in: .global)]) })
            .background(drag.target == id ? DayTheme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
    }
}

struct HomeDragSource: ViewModifier {
    let id: String
    @ObservedObject private var drag = HomeDrag.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var holding = false
    private var lifted: Bool { drag.item == id }
    func body(content: Content) -> some View {
        content
            .scaleEffect(lifted && !reduceMotion ? 1.025 : 1)
            .shadow(color: .black.opacity(lifted ? 0.12 : 0), radius: 12, y: 6)
            .offset(lifted ? drag.translation : .zero)
            .zIndex(lifted ? 100 : 0)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35, maximumDistance: 12)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .updating($holding) { value, state, _ in
                    switch value { case .second(true, _): state = true; default: break }
                }
                .onChanged { value in
                    if case .second(true, let movement) = value {
                        drag.lift(id)
                        if let movement { drag.update(movement) }
                    }
                }
                .onEnded { value in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        if case .second(true, let movement?) = value { drag.finish(at: movement.location) }
                        else { drag.reset() }
                    }
                })
            .onChange(of: holding) { _, value in
                if !value && lifted { Task { try? await Task.sleep(for: .milliseconds(100)); if !holding && drag.item == id { drag.reset() } } }
            }
            .onDisappear { if lifted { drag.reset() } }
    }
}
