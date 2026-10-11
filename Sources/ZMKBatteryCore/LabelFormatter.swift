public enum CentralPosition: String, Sendable, CaseIterable {
    case left
    case right
}

public struct LabelFormatter: Sendable {
    /// Assumed shape before a keyboard has been seen: a two-part split.
    public static let defaultLayout: [Role] = [.central, .peripheral(0)]

    public var centralPosition: CentralPosition
    public var separator: String
    public var placeholder: String

    public init(centralPosition: CentralPosition = .left, separator: String = " | ", placeholder: String = "--") {
        self.centralPosition = centralPosition
        self.separator = separator
        self.placeholder = placeholder
    }

    /// Peripherals keep their index order; the central goes first or last.
    public func order(_ roles: some Sequence<Role>) -> [Role] {
        let sorted = Array(Set(roles)).sorted()
        guard centralPosition == .right, sorted.first == .central else { return sorted }
        return Array(sorted.dropFirst()) + [.central]
    }

    public func label(layout: some Sequence<Role>, levels: [Role: Int]) -> String {
        order(layout)
            .map { "\(levels[$0].map(String.init) ?? placeholder)%" }
            .joined(separator: separator)
    }
}
