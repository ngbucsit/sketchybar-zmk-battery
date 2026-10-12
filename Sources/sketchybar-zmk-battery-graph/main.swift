import AppKit
import SwiftUI
import ZMKBatteryCore

/// Borderless panels can't become key by default; we need key status for Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class GraphApp: NSObject, NSApplicationDelegate {
    /// Clicks this close to the top of the screen land on SketchyBar; its click_script
    /// toggles this window, so don't also close on them.
    private static let barHeight: CGFloat = 60
    private static let refreshInterval: TimeInterval = 15

    private let model = HistoryModel(store: HistoryStore())
    private var panel: KeyPanel?
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let style = BarStyle.query()
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        let size = hosting.fittingSize

        let background = Self.makeBackground(size: size, style: style)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        let panel = KeyPanel(
            contentRect: NSRect(origin: position(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A shadow also draws a light rim around the window, so follow the bar's `shadow`.
        panel.hasShadow = style?.shadow ?? true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let style {
            // Match the bar's text: light on a dark bar.
            panel.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
            WindowBlur.apply(radius: style.blurRadius, to: panel)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        installDismissHandlers()
        Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.model.reload() }
        }
    }

    /// The bar's color, corner radius and border when SketchyBar can be queried; otherwise a
    /// standard popover background.
    private static func makeBackground(size: NSSize, style: BarStyle?) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        let view: NSView
        if let style {
            view = NSView(frame: frame)
            view.wantsLayer = true
            view.layer?.backgroundColor = cgColor(style.color)
            view.layer?.cornerRadius = style.cornerRadius
            view.layer?.borderWidth = style.borderWidth
            view.layer?.borderColor = cgColor(style.borderColor)
        } else {
            let effect = NSVisualEffectView(frame: frame)
            effect.material = .popover
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            view = effect
        }
        view.layer?.masksToBounds = true
        return view
    }

    private static func cgColor(_ argb: UInt32) -> CGColor {
        let c = BarStyle.components(argb)
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// Centered under the mouse (where the bar item was clicked), kept on screen.
    private func position(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let x = min(max(mouse.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = min(mouse.y - 24, bounds.maxY) - size.height
        return NSPoint(x: x, y: max(y, bounds.minY))
    }

    private func installDismissHandlers() {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            switch event.keyCode {
            case 53: NSApp.terminate(nil)  // Esc
            case 123: self.model.select(self.model.interval.shorter)  // ←
            case 124: self.model.select(self.model.interval.longer)  // →
            default: return event
            }
            return nil
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated {
                let mouse = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
                let onBar = screen.map { mouse.y >= $0.frame.maxY - Self.barHeight } ?? false
                if !onBar { NSApp.terminate(nil) }
            }
        }) {
            monitors.append(monitor)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

/// `--snapshot PATH [--interval 15m]` renders the chart to a PNG and exits (for checking the
/// layout or docs).
@MainActor
private func snapshot(to path: String, interval: GraphInterval) -> Never {
    // Approximates the window over a dark wallpaper; the real blur can't be captured here.
    let dark = BarStyle.query()?.isDark ?? false
    let model = HistoryModel(store: HistoryStore())
    model.select(interval)
    let view = HistoryView(model: model)
        .background(dark ? Color(white: 0.18) : Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
          (try? png.write(to: URL(fileURLWithPath: path))) != nil
    else {
        FileHandle.standardError.write(Data("failed to write snapshot to \(path)\n".utf8))
        exit(1)
    }
    exit(0)
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count {
    let interval = arguments.firstIndex(of: "--interval")
        .flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        .flatMap { label in GraphInterval.allCases.first { $0.label == label } }
    MainActor.assumeIsolated { snapshot(to: arguments[flag + 1], interval: interval ?? .default) }
}

let app = NSApplication.shared
private let delegate = GraphApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
