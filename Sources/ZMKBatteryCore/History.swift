import Foundation

/// One line of the history file: either a battery level or a disconnect marker.
public struct HistoryEntry: Codable, Equatable, Sendable {
    /// Unix time in seconds.
    public var t: Double
    /// Bluetooth identifier of the keyboard.
    public var device: String
    public var name: String?
    public var role: String?
    public var level: Int?
    public var event: String?

    public static let disconnectedEvent = "disconnected"

    public static func level(_ level: Int, role: Role, device: String, name: String?, at date: Date) -> HistoryEntry {
        HistoryEntry(t: date.timeIntervalSince1970, device: device, name: name, role: role.description, level: level)
    }

    public static func disconnected(device: String, at date: Date) -> HistoryEntry {
        HistoryEntry(t: date.timeIntervalSince1970, device: device, event: disconnectedEvent)
    }

    public var date: Date { Date(timeIntervalSince1970: t) }
    public var isDisconnect: Bool { event == Self.disconnectedEvent }
    public var parsedRole: Role? { role.flatMap(Role.init(_:)) }
}

extension Role {
    /// Parses the `description` form: "central" or "peripheral N".
    public init?(_ text: String) {
        if text == "central" {
            self = .central
        } else if text.hasPrefix("peripheral "), let index = Int(text.dropFirst("peripheral ".count)) {
            self = .peripheral(index)
        } else {
            return nil
        }
    }
}

/// Append-only JSON Lines file shared by the daemon (writer) and the graph viewer (reader).
public struct HistoryStore: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sketchybar-zmk-battery", isDirectory: true)
            .appendingPathComponent("history.jsonl")
    }

    public init(url: URL = HistoryStore.defaultURL) {
        self.url = url
    }

    public func append(_ entry: HistoryEntry) throws {
        var line = try JSONEncoder().encode(entry)
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: url)
        }
    }

    /// Skips lines that fail to decode rather than failing the whole file.
    public func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(HistoryEntry.self, from: $0) }
    }

    /// Drops entries older than `cutoff`, except the latest one per device and role (and the latest
    /// disconnect per device), so the level before the cutoff can still be carried forward.
    public func prune(olderThan cutoff: Date) throws {
        let entries = load()
        let kept = Self.pruned(entries, olderThan: cutoff)
        guard kept.count != entries.count else { return }
        let encoder = JSONEncoder()
        var data = Data()
        for entry in kept {
            data.append(try encoder.encode(entry))
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url, options: .atomic)
    }

    static func pruned(_ entries: [HistoryEntry], olderThan cutoff: Date) -> [HistoryEntry] {
        let threshold = cutoff.timeIntervalSince1970
        var latestOld: [String: Int] = [:]
        for (index, entry) in entries.enumerated() where entry.t < threshold {
            latestOld["\(entry.device)|\(entry.role ?? entry.event ?? "")"] = index
        }
        let keep = Set(latestOld.values)
        return entries.enumerated()
            .filter { $0.element.t >= threshold || keep.contains($0.offset) }
            .map(\.element)
    }
}

public struct HistoryPoint: Equatable, Sendable {
    public let date: Date
    public let level: Int

    public init(date: Date, level: Int) {
        self.date = date
        self.level = level
    }
}

/// A connected stretch of one role's levels. Points form an explicit staircase (a level change
/// adds the old and new level at the same instant), so it can be drawn with straight lines.
public struct HistorySegment: Equatable, Sendable, Identifiable {
    public let id: Int
    public var points: [HistoryPoint]

    public init(id: Int, points: [HistoryPoint]) {
        self.id = id
        self.points = points
    }
}

public enum HistorySeries {
    /// The device of the most recent level entry, with its last known name.
    public static func latestDevice(in entries: [HistoryEntry]) -> (id: String, name: String?)? {
        guard let last = entries.last(where: { $0.level != nil }) else { return nil }
        let name = entries.last { $0.device == last.device && $0.name != nil }?.name
        return (last.device, name)
    }

    public static func roles(in entries: [HistoryEntry], device: String) -> [Role] {
        Set(entries.filter { $0.device == device }.compactMap(\.parsedRole)).sorted()
    }

    /// ZMK derives the level from battery voltage, which sags under load and recovers at rest, so
    /// readings bounce by 1% around a boundary. Rises this small are treated as noise; drops and
    /// larger rises (charging) are kept.
    public static let defaultNoiseTolerance = 1

    /// The level to show after `reading`, given the level currently shown.
    static func smoothed(_ reading: Int, after shown: Int?, tolerance: Int) -> Int {
        guard let shown, reading > shown, reading - shown <= tolerance else { return reading }
        return shown
    }

    public static func segments(
        entries: [HistoryEntry],
        device: String,
        role: Role,
        window: DateInterval,
        noiseTolerance: Int = defaultNoiseTolerance
    ) -> [HistorySegment] {
        let relevant = entries
            .filter { $0.device == device && ($0.isDisconnect || $0.parsedRole == role) }
            .sorted { $0.t < $1.t }

        var segments: [HistorySegment] = []
        var current: [HistoryPoint] = []
        var level: Int?

        func close(at date: Date) {
            if let level, !current.isEmpty {
                current.append(HistoryPoint(date: date, level: level))
            }
            if !current.isEmpty {
                segments.append(HistorySegment(id: segments.count, points: current))
            }
            current = []
        }

        var index = relevant.startIndex
        // State before the window: only the latest level (or disconnect) matters.
        while index < relevant.endIndex, relevant[index].date < window.start {
            let entry = relevant[index]
            level = entry.isDisconnect ? nil : entry.level.map { smoothed($0, after: level, tolerance: noiseTolerance) }
            index += 1
        }
        if let level {
            current = [HistoryPoint(date: window.start, level: level)]
        }

        while index < relevant.endIndex, relevant[index].date <= window.end {
            let entry = relevant[index]
            index += 1
            if entry.isDisconnect {
                close(at: entry.date)
                level = nil
            } else if let reading = entry.level {
                let newLevel = smoothed(reading, after: level, tolerance: noiseTolerance)
                // Unchanged (repeat reads, filtered noise): the step just continues.
                if newLevel == level, !current.isEmpty { continue }
                if let level, !current.isEmpty {
                    current.append(HistoryPoint(date: entry.date, level: level))
                }
                current.append(HistoryPoint(date: entry.date, level: newLevel))
                level = newLevel
            }
        }
        close(at: window.end)
        return segments
    }

    /// The level at the end of the window, or nil if the device was disconnected by then.
    public static func currentLevel(_ segments: [HistorySegment], window: DateInterval) -> Int? {
        guard let last = segments.last?.points.last, last.date >= window.end else { return nil }
        return last.level
    }
}
