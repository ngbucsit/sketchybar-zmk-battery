import Charts
import SwiftUI
import ZMKBatteryCore

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var interval = GraphInterval.default
    @Published private(set) var window = GraphInterval.default.window(endingAt: Date())

    private let store: HistoryStore
    /// What `entries` was loaded from; reload() skips decoding while the file is unchanged.
    private var loaded: HistorySignature?

    init(store: HistoryStore) {
        self.store = store
        reload()
    }

    func reload() {
        let signature = store.signature()
        if signature == nil || signature != loaded {
            entries = store.load()
            loaded = signature
        }
        window = interval.window(endingAt: Date())
    }

    func select(_ newInterval: GraphInterval) {
        guard newInterval != interval else { return }
        interval = newInterval
        window = interval.window(endingAt: Date())
    }

    var device: (id: String, name: String?)? { HistorySeries.latestDevice(in: entries) }

    var roles: [Role] {
        guard let device else { return [] }
        return HistorySeries.roles(in: entries, device: device.id)
    }

    func segments(for role: Role) -> [HistorySegment] {
        guard let device else { return [] }
        return HistorySeries.segments(entries: entries, device: device.id, role: role, window: window)
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.device?.name ?? "Keyboard").font(.headline)
                Spacer()
                IntervalPicker(interval: model.interval)
            }
            if model.roles.isEmpty {
                Text("No battery history yet. Recording since the daemon started.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(model.roles, id: \.self) { role in
                    RoleChart(
                        title: title(for: role),
                        segments: model.segments(for: role),
                        window: model.window,
                        interval: model.interval
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func title(for role: Role) -> String {
        switch role {
        case .central: "Central"
        case .peripheral(let index):
            model.roles.filter(\.isPeripheral).count > 1 ? "Peripheral \(index + 1)" : "Peripheral"
        }
    }
}

/// Shows the interval with arrows hinting at the ←/→ keys; an arrow dims at the end of the range.
private struct IntervalPicker: View {
    let interval: GraphInterval

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .opacity(interval.shorter == interval ? 0.3 : 1)
            Text("\(interval.label) · last \(GraphInterval.tickLabel(secondsAgo: interval.span).dropFirst())")
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .opacity(interval.longer == interval ? 0.3 : 1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct RoleChart: View {
    let title: String
    let segments: [HistorySegment]
    let window: DateInterval
    let interval: GraphInterval

    private struct Step: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let level: Int
    }

    /// Flat stretches of the staircase: consecutive points with the same level.
    private var steps: [Step] {
        var steps: [Step] = []
        for segment in segments {
            for (from, to) in zip(segment.points, segment.points.dropFirst())
            where from.level == to.level && from.date < to.date {
                steps.append(Step(id: steps.count, start: from.date, end: to.date, level: from.level))
            }
        }
        return steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(HistorySeries.currentLevel(segments, window: window).map { "\($0)%" } ?? "--%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Chart {
                // AreaMark can't fill a staircase (two points share each step's x), so fill each
                // flat step with its own rectangle.
                ForEach(steps) { step in
                    RectangleMark(
                        xStart: .value("Start", step.start),
                        xEnd: .value("End", step.end),
                        yStart: .value("Floor", 0),
                        yEnd: .value("Level", step.level)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                }
                ForEach(segments) { segment in
                    ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Level", point.level),
                            series: .value("Segment", segment.id)
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartXScale(domain: window.start...window.end)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: interval.ticks(endingAt: window.end)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        let secondsAgo = window.end.timeIntervalSince(date)
                        let label = interval.tickLabel(secondsAgo: secondsAgo)
                        // Edge labels are anchored inward so they aren't clipped.
                        if secondsAgo < 1 {
                            AxisValueLabel(label, anchor: .topTrailing)
                        } else if secondsAgo >= interval.span - 1 {
                            AxisValueLabel(label, anchor: .topLeading)
                        } else {
                            AxisValueLabel(label, anchor: .top)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisTick()
                    if let level = value.as(Int.self) {
                        AxisValueLabel("\(level)%")
                    }
                }
            }
            .frame(height: 160)
        }
    }
}
