import SwiftUI

/// Debug builds launched with --render-counts: counts how often key views redraw, shown in a small label
/// that UI tests read (testTodayScrollingRedraws). Release builds count nothing.
@MainActor final class RenderCounter {
    static let shared = RenderCounter()
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.arguments.contains("--render-counts")
    #else
    static let enabled = false
    #endif
    private(set) var counts: [String: Int] = [:]
    static func hit(_ name: String) {
        guard enabled else { return }
        shared.counts[name, default: 0] += 1
    }
    func reset() { counts = [:] }
    var summary: String { counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") }
}

/// The counts, refreshed twice a second, and a button that resets them. Only with --render-counts.
struct RenderCountsBadge: View {
    var body: some View {
        if RenderCounter.enabled {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Button { RenderCounter.shared.reset() } label: {
                    Text(RenderCounter.shared.summary).font(.system(size: 8)).lineLimit(3)
                }
                .accessibilityIdentifier("render-counts").accessibilityLabel(RenderCounter.shared.summary)
            }
            .frame(maxWidth: 300, alignment: .leading).padding(.top, 2)
        }
    }
}
