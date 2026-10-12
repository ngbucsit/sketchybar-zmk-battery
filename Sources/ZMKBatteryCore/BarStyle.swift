import Foundation

public enum SketchyBarExecutable {
    /// Uses `path` if given, otherwise searches PATH plus the usual Homebrew prefixes
    /// (launchd-started processes often have a minimal PATH).
    public static func locate(path: String? = nil) -> URL? {
        let fileManager = FileManager.default
        if let path {
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = (searchPath + ["/opt/homebrew/bin", "/usr/local/bin"]).map { "\($0)/sketchybar" }
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

/// The bar's look from `sketchybar --query bar`, so other windows can match it.
public struct BarStyle: Equatable, Sendable {
    /// 0xAARRGGBB, as SketchyBar writes colors.
    public var color: UInt32
    public var blurRadius: Int
    public var cornerRadius: Double
    public var borderWidth: Double
    public var borderColor: UInt32
    public var shadow: Bool

    public init(
        color: UInt32,
        blurRadius: Int,
        cornerRadius: Double,
        borderWidth: Double,
        borderColor: UInt32,
        shadow: Bool = false
    ) {
        self.color = color
        self.blurRadius = blurRadius
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.shadow = shadow
    }

    public init?(queryOutput data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let color = (json["color"] as? String).flatMap(Self.parseColor)
        else { return nil }
        self.color = color
        blurRadius = (json["blur_radius"] as? NSNumber)?.intValue ?? 0
        cornerRadius = (json["corner_radius"] as? NSNumber)?.doubleValue ?? 0
        borderWidth = (json["border_width"] as? NSNumber)?.doubleValue ?? 0
        borderColor = (json["border_color"] as? String).flatMap(Self.parseColor) ?? 0
        shadow = (json["shadow"] as? String) == "on"
    }

    /// Runs `sketchybar --query bar`; nil if SketchyBar isn't installed or running.
    public static func query(executable: URL? = SketchyBarExecutable.locate()) -> BarStyle? {
        guard let executable else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--query", "bar"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return BarStyle(queryOutput: data)
    }

    /// Parses "0xAARRGGBB".
    public static func parseColor(_ text: String) -> UInt32? {
        let hex = text.lowercased().hasPrefix("0x") ? text.dropFirst(2) : Substring(text)
        return UInt32(hex, radix: 16)
    }

    /// RGBA components in 0...1.
    public static func components(_ argb: UInt32) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        func channel(_ shift: UInt32) -> Double { Double((argb >> shift) & 0xFF) / 255 }
        return (channel(16), channel(8), channel(0), channel(24))
    }

    /// Whether light text reads best on the bar's color.
    public var isDark: Bool {
        let c = Self.components(color)
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.5
    }
}
