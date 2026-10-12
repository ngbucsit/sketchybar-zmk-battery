// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "sketchybar-zmk-battery",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sketchybar-zmk-battery", targets: ["sketchybar-zmk-battery"]),
        .executable(name: "sketchybar-zmk-battery-graph", targets: ["sketchybar-zmk-battery-graph"]),
    ],
    targets: [
        // Pure logic (classification, formatting, flags) so it can be unit-tested without Bluetooth.
        .target(name: "ZMKBatteryCore"),
        .executableTarget(
            name: "sketchybar-zmk-battery",
            dependencies: ["ZMKBatteryCore"],
            linkerSettings: [
                // CoreBluetooth requires NSBluetoothAlwaysUsageDescription; a bare CLI has no bundle,
                // so embed the Info.plist directly in the binary.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Support/Info.plist",
                ]),
            ]
        ),
        // Separate from the daemon so the daemon never loads AppKit/SwiftUI.
        .executableTarget(name: "sketchybar-zmk-battery-graph", dependencies: ["ZMKBatteryCore"]),
        .testTarget(name: "ZMKBatteryCoreTests", dependencies: ["ZMKBatteryCore"]),
    ],
    swiftLanguageModes: [.v6]
)
