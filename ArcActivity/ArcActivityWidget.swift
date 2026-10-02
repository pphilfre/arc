import ActivityKit
import SwiftUI
import WidgetKit

@main struct ArcWidgets: WidgetBundle {
    var body: some Widget { ArcJourneyActivity() }
}

struct ArcJourneyActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ArcActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.attributes.isNavigation ? context.state.symbol : "speedometer")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(.blue).frame(width: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.attributes.isNavigation ? context.state.instruction : "\(context.state.currentSpeed) \(context.state.units)")
                        .font(.headline).lineLimit(2)
                    if context.attributes.isNavigation {
                        Text(context.state.arrived ? context.attributes.destination : "\(context.state.distanceToTurn) · \(context.attributes.destination)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Average \(context.state.averageSpeed) \(context.state.units) · \(context.state.sessionDistance)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if context.attributes.isNavigation {
                        Text(context.state.arrival, style: .time).font(.headline).monospacedDigit()
                        Text(context.state.remainingDistance).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(context.state.startedAt, style: .timer).monospacedDigit().font(.headline)
                        Text("elapsed").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(20)
                .activityBackgroundTint(.black.opacity(0.05))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.isNavigation ? context.state.symbol : "speedometer")
                        .font(.title2).foregroundStyle(.blue).padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.isNavigation {
                        Text(context.state.arrival, style: .time).font(.headline).monospacedDigit()
                    } else { Text("\(context.state.currentSpeed)").font(.title2.bold()).monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.isNavigation ? context.state.distanceToTurn : context.state.units)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.isNavigation ? context.state.instruction : "Average \(context.state.averageSpeed) \(context.state.units)")
                            .font(.subheadline).lineLimit(2)
                        HStack {
                            Text(context.attributes.isNavigation ? context.attributes.destination : context.state.sessionDistance).lineLimit(1)
                            Spacer()
                            if context.attributes.isNavigation { Text(context.state.remainingDistance) }
                            else { Text(context.state.startedAt, style: .timer).monospacedDigit() }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: context.attributes.isNavigation ? context.state.symbol : "speedometer").foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.attributes.isNavigation ? context.state.distanceToTurn : "\(context.state.currentSpeed)")
                    .font(.caption).monospacedDigit()
            } minimal: {
                Image(systemName: context.attributes.isNavigation ? context.state.symbol : "speedometer").foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

