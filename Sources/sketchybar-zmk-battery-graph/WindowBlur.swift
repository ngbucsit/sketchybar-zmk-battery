import AppKit

/// Background blur through SkyLight, the private call SketchyBar uses for `blur_radius`, so the
/// window blurs exactly like the bar. Looked up at runtime: if it's missing, there's no blur.
@MainActor
enum WindowBlur {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetBlurRadius = @convention(c) (Int32, UInt32, UInt32) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    @discardableResult
    static func apply(radius: Int, to window: NSWindow) -> Bool {
        guard radius > 0,
              let skyLight,
              let connection = dlsym(skyLight, "SLSMainConnectionID"),
              let setBlur = dlsym(skyLight, "SLSSetWindowBackgroundBlurRadius")
        else { return false }
        let connectionID = unsafeBitCast(connection, to: MainConnection.self)()
        let status = unsafeBitCast(setBlur, to: SetBlurRadius.self)(connectionID, UInt32(window.windowNumber), UInt32(radius))
        return status == 0
    }
}
