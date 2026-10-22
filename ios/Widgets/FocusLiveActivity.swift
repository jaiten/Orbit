import ActivityKit
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.isStale ? "Focus finished" : "One thing at a time").font(.caption).foregroundStyle(.secondary)
                    Text(context.attributes.title).font(.headline).lineLimit(2)
                }
                Spacer()
                if context.isStale { Image(systemName: "checkmark.circle") }
                else { Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true).monospacedDigit().frame(width: 80) }
            }.padding().activityBackgroundTint(Color(.secondarySystemBackground))
                .widgetURL(URL(string: "orbit://focus"))
        } dynamicIsland: { context in
            DynamicIsland(expanded: {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true).monospacedDigit().frame(width: 70)
                }
                DynamicIslandExpandedRegion(.bottom) { Text(context.attributes.title).font(.headline).lineLimit(2) }
            }, compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }, compactTrailing: {
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true).monospacedDigit().frame(width: 45)
            }, minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            })
                .widgetURL(URL(string: "orbit://focus"))
        }
    }
}
