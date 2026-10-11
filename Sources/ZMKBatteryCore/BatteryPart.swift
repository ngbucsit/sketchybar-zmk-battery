import Foundation

/// Which half (or part) of a keyboard a battery level belongs to.
/// Ordering: central first, then peripherals by index.
public enum Role: Hashable, Comparable, Sendable, CustomStringConvertible {
    case central
    case peripheral(Int)

    public var isPeripheral: Bool {
        if case .peripheral = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .central: "central"
        case .peripheral(let index): "peripheral \(index)"
        }
    }
}

/// Classifies Battery Level characteristics using the descriptors ZMK attaches to them.
///
/// With `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY`, the central exposes a second Battery
/// Service whose levels carry a User Description of "Peripheral N" and a Presentation Format
/// description of 0x0108 ("auxiliary"). See zmk/app/src/split/bluetooth/central_bas_proxy.c.
public enum Classifier {
    public static let auxiliaryDescription: UInt16 = 0x0108

    /// Parses "Peripheral N" into N.
    public static func peripheralIndex(fromUserDescription text: String?) -> Int? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let prefix = "Peripheral "
        guard trimmed.hasPrefix(prefix) else { return nil }
        return Int(trimmed.dropFirst(prefix.count))
    }

    /// Extracts the 16-bit description field from a Characteristic Presentation Format value
    /// (format, exponent, unit[2], namespace, description[2], little-endian).
    public static func presentationDescription(from data: Data) -> UInt16? {
        guard data.count >= 7 else { return nil }
        let start = data.startIndex
        return UInt16(data[start + 5]) | UInt16(data[start + 6]) << 8
    }

    /// - Parameter nextPeripheralIndex: used when a level is marked auxiliary but carries no
    ///   "Peripheral N" description.
    public static func role(
        userDescription: String?,
        presentationDescription: UInt16?,
        nextPeripheralIndex: Int
    ) -> Role {
        if let index = peripheralIndex(fromUserDescription: userDescription) {
            return .peripheral(index)
        }
        if presentationDescription == auxiliaryDescription {
            return .peripheral(nextPeripheralIndex)
        }
        return .central
    }
}
