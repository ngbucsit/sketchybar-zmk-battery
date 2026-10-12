import Foundation
import ZMKBatteryCore

struct SketchyBar {
    let executable: URL

    init?(path: String?) {
        guard let executable = SketchyBarExecutable.locate(path: path) else { return nil }
        self.executable = executable
    }

    func set(item: String, label: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--set", item, "label=\(label)"]
        do {
            try process.run()
        } catch {
            log("failed to run sketchybar: \(error)")
        }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("sketchybar-zmk-battery: \(message)\n".utf8))
}
