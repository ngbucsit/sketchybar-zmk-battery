import Foundation

/// Spacing between X-axis ticks in the history graph. Each shows `tickCount` ticks ending at now.
public enum GraphInterval: Int, CaseIterable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case twoHours

    public static let tickCount = 7
    public static let `default` = GraphInterval.thirtyMinutes

    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .twoHours: 2 * 3600
        }
    }

    public var label: String { Self.format(seconds) }

    /// Time covered: from the oldest tick to now.
    public var span: TimeInterval { seconds * Double(Self.tickCount - 1) }

    /// Next shorter/longer interval, staying put at either end.
    public var shorter: GraphInterval { GraphInterval(rawValue: rawValue - 1) ?? self }
    public var longer: GraphInterval { GraphInterval(rawValue: rawValue + 1) ?? self }

    public func window(endingAt end: Date) -> DateInterval {
        DateInterval(start: end.addingTimeInterval(-span), end: end)
    }

    /// Oldest first, ending at `end`.
    public func ticks(endingAt end: Date) -> [Date] {
        (0..<Self.tickCount).reversed().map { end.addingTimeInterval(-Double($0) * seconds) }
    }

    /// Tick label for this spacing. Short spacings use plain minutes ("-90m", not "-1h30m"), so
    /// the labels stay narrow enough not to overlap.
    public func tickLabel(secondsAgo: TimeInterval) -> String {
        guard seconds < 30 * 60 else { return Self.tickLabel(secondsAgo: secondsAgo) }
        let minutes = Int((secondsAgo / 60).rounded())
        return minutes == 0 ? "now" : "-\(minutes)m"
    }

    /// "now", "-45m", "-1h15m", "-10h".
    public static func tickLabel(secondsAgo: TimeInterval) -> String {
        let rounded = (secondsAgo / 60).rounded() * 60
        return rounded == 0 ? "now" : "-\(format(rounded))"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }
}
