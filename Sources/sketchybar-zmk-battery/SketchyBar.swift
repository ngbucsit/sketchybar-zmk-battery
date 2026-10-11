import Foundation

struct SketchyBar {
    let executable: URL

    /// Uses `path` if given, otherwise searches PATH plus the usual Homebrew prefixes
    /// (launchd-started processes often have a minimal PATH).
    init?(path: String?) {
        let fileManager = FileManager.default
        if let path {
            guard fileManager.isExecutableFile(atPath: path) else { return nil }
            executable = URL(fileURLWithPath: path)
            return
        }
        let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = (searchPath + ["/opt/homebrew/bin", "/usr/local/bin"]).map { "\($0)/sketchybar" }
        guard let found = candidates.first(where: fileManager.isExecutableFile(atPath:)) else { return nil }
        executable = URL(fileURLWithPath: found)
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
