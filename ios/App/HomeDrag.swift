import SwiftUI
import UIKit

/// A held item moves in the same scroll surface. A quick horizontal gesture
/// remains a swipe; it cannot become a deletion reveal after the item is lifted.
/// The hold is deliberately long and must stay almost still, so a finger that
/// starts scrolling over a tile scrolls the page instead of picking the tile up.
@MainActor final class HomeDrag: ObservableObject {
    static let shared = HomeDrag()
    /// How long a tile is held before it lifts, and how far the finger may wander meanwhile.
    static let holdDuration = 0.6
    static let holdTolerance: CGFloat = 6
    @Published private(set) var item: String?
    @Published var translation: CGSize = .zero
    @Published private(set) var target: String?
    @Published private(set) var source: String?
    /// Drop areas and tiles, in `.global` (window) coordinates.
    var frames: [String: CGRect] = [:]
    var tiles: [String: CGRect] = [:]
    func tile(at point: CGPoint) -> String? { tiles.first { $0.value.contains(point) }?.key }
    /// UI tests only: what the hold recognizer saw, shown in a hidden label so a failing test can report it.
    @Published var trace = ""
    static let tracing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    func note(_ text: String) { if Self.tracing { trace = String((trace + " | " + text).suffix(600)) } }
    var accept: ((String, Bool) -> Void)?
    func lift(_ id: String) {
        guard item != id else { return }
        item = id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func update(_ value: DragGesture.Value) { update(start: value.startLocation, location: value.location) }
    func update(start: CGPoint, location: CGPoint) {
        if source == nil { source = frames.first { $0.value.contains(start) }?.key }
        translation = CGSize(width: location.x - start.x, height: location.y - start.y)
        target = frames.first { $0.value.contains(location) }?.key
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
    @Environment(\.orbitAccent) private var accent
    @ObservedObject private var drag = HomeDrag.shared
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .background(GeometryReader { proxy in Color.clear.preference(key: HomeDropFrames.self, value: [id: proxy.frame(in: .global)]) })
            .background(drag.target == id ? accent.fill.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: DayTheme.rowRadius, style: .continuous))
    }
}

struct HomeTileFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

/// A tile that can be held and moved. The hold itself is `TileHoldInstaller`, one recognizer on the
/// scroll view; this reports where the tile is and draws it lifted.
struct HomeDragSource: ViewModifier {
    let id: String
    @ObservedObject private var drag = HomeDrag.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var lifted: Bool { drag.item == id }
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in Color.clear.preference(key: HomeTileFrames.self, value: [id: proxy.frame(in: .global)]) })
            .scaleEffect(lifted && !reduceMotion ? 1.025 : 1)
            .shadow(color: .black.opacity(lifted ? 0.12 : 0), radius: 12, y: 6)
            .offset(lifted ? drag.translation : .zero)
            .zIndex(lifted ? 100 : 0)
            .onDisappear { if lifted { drag.reset() } }
    }
}
