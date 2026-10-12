import Foundation
import Testing
@testable import ZMKBatteryCore

@Suite struct HistoryTests {
    let device = "D1"
    let end = Date(timeIntervalSince1970: 100_000)
    var window: DateInterval { DateInterval(start: end.addingTimeInterval(-12 * 3600), end: end) }

    func level(_ level: Int, _ role: Role = .central, hoursAgo: Double) -> HistoryEntry {
        .level(level, role: role, device: device, name: "Lily58", at: end.addingTimeInterval(-hoursAgo * 3600))
    }

    func disconnected(hoursAgo: Double) -> HistoryEntry {
        .disconnected(device: device, at: end.addingTimeInterval(-hoursAgo * 3600))
    }

    func points(_ segment: HistorySegment) -> [[Double]] {
        segment.points.map { [($0.date.timeIntervalSince(end) / 3600).rounded(), Double($0.level)] }
    }

    @Test func roleRoundTrip() {
        for role in [Role.central, .peripheral(0), .peripheral(3)] {
            #expect(Role(role.description) == role)
        }
        #expect(Role("left") == nil)
    }

    @Test func storeAppendsAndPrunes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("history.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HistoryStore(url: url)

        try store.append(level(90, hoursAgo: 30))
        try store.append(level(80, hoursAgo: 26))
        try store.append(level(70, .peripheral(0), hoursAgo: 25))
        try store.append(level(60, hoursAgo: 1))
        #expect(store.load().count == 4)

        try store.prune(olderThan: end.addingTimeInterval(-24 * 3600))
        // The latest pre-cutoff entry per role survives so its level can be carried forward.
        #expect(store.load().map(\.level) == [80, 70, 60])
    }

    @Test func carriesLevelForwardFromBeforeWindow() {
        let segments = HistorySeries.segments(
            entries: [level(90, hoursAgo: 20), level(70, hoursAgo: 6)],
            device: device, role: .central, window: window
        )
        #expect(segments.count == 1)
        #expect(points(segments[0]) == [[-12, 90], [-6, 90], [-6, 70], [0, 70]])
        #expect(HistorySeries.currentLevel(segments, window: window) == 70)
    }

    @Test func disconnectSplitsSegments() {
        let segments = HistorySeries.segments(
            entries: [level(80, hoursAgo: 10), disconnected(hoursAgo: 8), level(75, hoursAgo: 5)],
            device: device, role: .central, window: window
        )
        #expect(segments.map(points) == [[[-10, 80], [-8, 80]], [[-5, 75], [0, 75]]])
    }

    @Test func disconnectedAtEndHasNoCurrentLevel() {
        let segments = HistorySeries.segments(
            entries: [level(80, hoursAgo: 3), disconnected(hoursAgo: 1)],
            device: device, role: .central, window: window
        )
        #expect(segments.map(points) == [[[-3, 80], [-1, 80]]])
        #expect(HistorySeries.currentLevel(segments, window: window) == nil)
    }

    @Test func disconnectBeforeWindowStartsEmpty() {
        let segments = HistorySeries.segments(
            entries: [level(80, hoursAgo: 20), disconnected(hoursAgo: 14)],
            device: device, role: .central, window: window
        )
        #expect(segments.isEmpty)
    }

    @Test func filtersByRoleAndDevice() {
        var other = level(10, hoursAgo: 2)
        other.device = "D2"
        let entries = [level(50, .peripheral(0), hoursAgo: 4), level(40, hoursAgo: 4), other]
        let segments = HistorySeries.segments(entries: entries, device: device, role: .peripheral(0), window: window)
        #expect(segments.map(points) == [[[-4, 50], [0, 50]]])
        #expect(HistorySeries.roles(in: entries, device: device) == [.central, .peripheral(0)])
        #expect(HistorySeries.latestDevice(in: entries)?.id == "D2")
    }
}

@Suite struct GraphIntervalTests {
    let now = Date(timeIntervalSince1970: 100_000)

    @Test func sevenTicksEndingNow() {
        for interval in GraphInterval.allCases {
            let ticks = interval.ticks(endingAt: now)
            #expect(ticks.count == 7)
            #expect(ticks.last == now)
            #expect(ticks.first == interval.window(endingAt: now).start)
        }
        #expect(GraphInterval.twoHours.span == 12 * 3600)
        #expect(GraphInterval.fifteenMinutes.span == 90 * 60)
    }

    @Test func stepsStopAtEnds() {
        #expect(GraphInterval.fifteenMinutes.shorter == .fifteenMinutes)
        #expect(GraphInterval.fifteenMinutes.longer == .thirtyMinutes)
        #expect(GraphInterval.thirtyMinutes.longer == .twoHours)
        #expect(GraphInterval.twoHours.longer == .twoHours)
        #expect(GraphInterval.default == .thirtyMinutes)
    }

    @Test func labels() {
        #expect(GraphInterval.allCases.map(\.label) == ["15m", "30m", "2h"])
        let fifteen = GraphInterval.fifteenMinutes.ticks(endingAt: now).map { GraphInterval.fifteenMinutes.tickLabel(secondsAgo: now.timeIntervalSince($0)) }
        #expect(fifteen == ["-90m", "-75m", "-60m", "-45m", "-30m", "-15m", "now"])
        let thirty = GraphInterval.thirtyMinutes.ticks(endingAt: now).map { GraphInterval.thirtyMinutes.tickLabel(secondsAgo: now.timeIntervalSince($0)) }
        #expect(thirty == ["-3h", "-2h30m", "-2h", "-1h30m", "-1h", "-30m", "now"])
        let two = GraphInterval.twoHours.ticks(endingAt: now).map { GraphInterval.twoHours.tickLabel(secondsAgo: now.timeIntervalSince($0)) }
        #expect(two == ["-12h", "-10h", "-8h", "-6h", "-4h", "-2h", "now"])
    }
}

@Suite struct HistoryNoiseTests {
    let device = "D1"
    let end = Date(timeIntervalSince1970: 100_000)
    var window: DateInterval { DateInterval(start: end.addingTimeInterval(-6 * 3600), end: end) }

    func levels(_ values: [(hoursAgo: Double, level: Int)]) -> [HistoryEntry] {
        values.map { .level($0.level, role: .central, device: device, name: nil, at: end.addingTimeInterval(-$0.hoursAgo * 3600)) }
    }

    func shownLevels(_ entries: [HistoryEntry], tolerance: Int = HistorySeries.defaultNoiseTolerance) -> [Int] {
        HistorySeries.segments(entries: entries, device: device, role: .central, window: window, noiseTolerance: tolerance)
            .flatMap(\.points).map(\.level)
    }

    @Test func ignoresOnePercentBounces() {
        // The real pattern from a Lily58: 59 → 58 → 59 → 58.
        let entries = levels([(5, 59), (4, 58), (3, 59), (2, 58)])
        #expect(shownLevels(entries) == [59, 59, 58, 58])
        #expect(shownLevels(entries, tolerance: 0) == [59, 59, 58, 58, 59, 59, 58, 58])
    }

    @Test func keepsChargingRises() {
        #expect(shownLevels(levels([(5, 40), (4, 42), (3, 45)])) == [40, 40, 42, 42, 45, 45])
    }

    @Test func skipsRepeatedReads() {
        #expect(shownLevels(levels([(5, 70), (4, 70), (3, 70)])) == [70, 70])
    }

    @Test func smoothsBeforeWindowToo() {
        // 1% rise just before the window is noise; the level carried in stays 50.
        #expect(shownLevels(levels([(8, 50), (7, 51)])) == [50, 50])
    }

    @Test func disconnectResetsBaseline() {
        var entries = levels([(5, 60)])
        entries.append(.disconnected(device: device, at: end.addingTimeInterval(-4 * 3600)))
        entries += levels([(3, 61)])
        #expect(shownLevels(entries) == [60, 60, 61, 61])
    }
}
