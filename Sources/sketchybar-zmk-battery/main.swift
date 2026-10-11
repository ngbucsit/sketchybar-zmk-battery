import Foundation
import ZMKBatteryCore

let config: Config
do {
    config = try Config.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    log("\(error)\n\n\(Config.usage)")
    exit(2)
}

if config.mode == .help {
    print(Config.usage)
    exit(0)
}

var bar: SketchyBar?
if config.mode == .daemon {
    bar = SketchyBar(path: config.sketchybarPath)
    if bar == nil {
        log("sketchybar not found; pass its location with --sketchybar PATH")
        exit(1)
    }
}

let monitor = BatteryMonitor(config: config, bar: bar)
dispatchMain()
