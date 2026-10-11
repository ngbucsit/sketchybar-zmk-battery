public struct Config: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case daemon
        case list
        case once
        case help
    }

    public var mode: Mode = .daemon
    public var item = "kb_batt"
    public var device: String?
    public var centralPosition: CentralPosition = .left
    public var separator = " | "
    public var sketchybarPath: String?
    public var verbose = false

    public init() {}

    public var formatter: LabelFormatter {
        LabelFormatter(centralPosition: centralPosition, separator: separator)
    }

    public static let usage = """
        Usage: sketchybar-zmk-battery [options]

        Shows the battery levels of a ZMK keyboard in a SketchyBar item, central half first.
        Runs as a daemon and updates the item whenever a level changes.

        Options:
          --item NAME            SketchyBar item to update (default: kb_batt)
          --device NAME          Match the keyboard by Bluetooth name (default: auto-detect a ZMK split)
          --central left|right   Side of the label the central half is shown on (default: left)
          --separator STR        Text between levels (default: " | ")
          --sketchybar PATH      Path to the sketchybar binary (default: search PATH)
          --list                 Print detected devices and their battery levels, then exit
          --once                 Print the label once, then exit
          --verbose              Log Bluetooth activity to stderr
          -h, --help             Show this help
        """

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownOption(String)
        case missingValue(String)
        case invalidValue(option: String, value: String)

        public var description: String {
            switch self {
            case .unknownOption(let option): "unknown option: \(option)"
            case .missingValue(let option): "missing value for \(option)"
            case .invalidValue(let option, let value): "invalid value for \(option): \(value)"
            }
        }
    }

    /// Accepts `--opt value` and `--opt=value`.
    public static func parse(_ arguments: [String]) throws(ParseError) -> Config {
        var config = Config()
        var remaining = arguments[...]

        while let argument = remaining.popFirst() {
            var option = argument
            var inlineValue: String?
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                option = String(argument[..<equals])
                inlineValue = String(argument[argument.index(after: equals)...])
            }

            func value() throws(ParseError) -> String {
                if let inlineValue { return inlineValue }
                guard let next = remaining.popFirst() else { throw .missingValue(option) }
                return next
            }

            switch option {
            case "--item": config.item = try value()
            case "--device": config.device = try value()
            case "--separator": config.separator = try value()
            case "--sketchybar": config.sketchybarPath = try value()
            case "--central":
                let raw = try value()
                guard let position = CentralPosition(rawValue: raw.lowercased()) else {
                    throw .invalidValue(option: option, value: raw)
                }
                config.centralPosition = position
            case "--list": config.mode = .list
            case "--once": config.mode = .once
            case "--verbose": config.verbose = true
            case "-h", "--help": config.mode = .help
            default: throw .unknownOption(argument)
            }
        }
        return config
    }
}
