import CoreBluetooth
import Foundation
import ZMKBatteryCore

private enum GATT {
    static var batteryService: CBUUID { CBUUID(string: "180F") }
    static var batteryLevel: CBUUID { CBUUID(string: "2A19") }
    static var userDescription: CBUUID { CBUUID(string: CBUUIDCharacteristicUserDescriptionString) }
    static var presentationFormat: CBUUID { CBUUID(string: CBUUIDCharacteristicFormatString) }
}

/// Battery state of one connected device, built up as GATT discovery callbacks arrive.
@MainActor
private final class Session {
    let peripheral: CBPeripheral
    var roles: [ObjectIdentifier: Role] = [:]
    var levels: [Role: Int] = [:]
    var userDescriptions: [ObjectIdentifier: String] = [:]
    var presentationDescriptions: [ObjectIdentifier: UInt16] = [:]
    var pendingDescriptorReads: [ObjectIdentifier: Int] = [:]
    var pendingLevelReads: Set<ObjectIdentifier> = []
    /// In-flight GATT requests; zero means discovery has settled.
    var outstanding = 0

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    var name: String { peripheral.name ?? "Unknown" }
    var isSplit: Bool { roles.values.contains(where: \.isPeripheral) }

    func reset() {
        roles = [:]
        levels = [:]
        userDescriptions = [:]
        presentationDescriptions = [:]
        pendingDescriptorReads = [:]
        pendingLevelReads = []
        outstanding = 0
    }
}

/// Finds the keyboard among devices macOS already has connected, subscribes to its battery levels,
/// and pushes a label to SketchyBar on every change. Never scans: reconnects use a pending
/// `connect`, which completes whenever the keyboard comes back.
@MainActor
final class BatteryMonitor: NSObject {
    private static let retryInterval: Duration = .seconds(30)
    private static let oneShotTimeout: Duration = .seconds(5)
    /// The graph shows 12 hours; keep a margin.
    private static let historyRetention: TimeInterval = 24 * 3600

    private let config: Config
    private let formatter: LabelFormatter
    private let bar: SketchyBar?
    private let history = HistoryStore()
    private var manager: CBCentralManager!

    private var sessions: [UUID: Session] = [:]
    private var sessionOrder: [UUID] = []
    /// Connected devices that turned out not to be the keyboard; skipped on retries.
    private var rejected: Set<UUID> = []
    private var selected: UUID?
    private var layout = LabelFormatter.defaultLayout
    private var lastLabel: String?
    private var retryScheduled = false

    init(config: Config, bar: SketchyBar?) {
        self.config = config
        self.formatter = config.formatter
        self.bar = bar
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
        if config.mode == .daemon {
            do {
                try history.prune(olderThan: Date().addingTimeInterval(-Self.historyRetention))
            } catch {
                verbose("failed to prune history: \(error)")
            }
        } else {
            Task {
                try? await Task.sleep(for: Self.oneShotTimeout)
                self.verbose("timed out waiting for Bluetooth")
                self.finishOneShot()
            }
        }
    }

    // MARK: Discovery

    private func discover() {
        let connected = manager.retrieveConnectedPeripherals(withServices: [GATT.batteryService])
        let candidates = connected.filter { peripheral in
            guard !rejected.contains(peripheral.identifier) else { return false }
            guard let device = config.device else { return true }
            return peripheral.name?.localizedCaseInsensitiveContains(device) ?? false
        }
        verbose("connected devices with a Battery Service: \(connected.map { $0.name ?? "Unknown" })")

        for peripheral in candidates where sessions[peripheral.identifier] == nil {
            let session = Session(peripheral: peripheral)
            sessions[peripheral.identifier] = session
            sessionOrder.append(peripheral.identifier)
            peripheral.delegate = self
            session.outstanding += 1
            manager.connect(peripheral)
        }
        checkSettled()
    }

    private func scheduleRetry() {
        guard config.mode == .daemon, !retryScheduled else { return }
        retryScheduled = true
        Task {
            try? await Task.sleep(for: Self.retryInterval)
            self.retryScheduled = false
            if self.selected == nil, self.manager.state == .poweredOn {
                self.discover()
            }
        }
    }

    private func session(for peripheral: CBPeripheral) -> Session? {
        sessions[peripheral.identifier]
    }

    private func classify(_ characteristic: CBCharacteristic, in session: Session) {
        let id = ObjectIdentifier(characteristic)
        let role = Classifier.role(
            userDescription: session.userDescriptions[id],
            presentationDescription: session.presentationDescriptions[id],
            nextPeripheralIndex: session.roles.values.filter(\.isPeripheral).count
        )
        guard !session.roles.values.contains(role) else {
            verbose("\(session.name): ignoring duplicate \(role) level")
            return
        }
        verbose("\(session.name): found \(role) level")
        session.roles[id] = role
        session.pendingLevelReads.insert(id)
        session.outstanding += 1
        session.peripheral.readValue(for: characteristic)
        session.peripheral.setNotifyValue(true, for: characteristic)
        selectIfNeeded(session)
    }

    private func selectIfNeeded(_ session: Session) {
        guard selected == nil else { return }
        let matches = config.device == nil ? session.isSplit : !session.roles.isEmpty
        guard matches else { return }
        selected = session.peripheral.identifier
        verbose("using \(session.name)")
        // Levels read before the keyboard was identified weren't recorded yet.
        for (role, level) in session.levels {
            record(.level(level, role: role, device: session.peripheral.identifier.uuidString, name: session.name, at: Date()))
        }
    }

    /// Called after every completed request. Once all sessions are idle, drops devices that
    /// aren't the keyboard and renders (or prints, in one-shot modes).
    private func checkSettled() {
        // The keyboard's label only depends on its own session; another device that is slow
        // (or stuck) answering discovery mustn't hold back updates.
        render()
        guard sessions.values.allSatisfy({ $0.outstanding == 0 }) else { return }

        if config.mode != .daemon {
            finishOneShot()
            return
        }
        for id in sessionOrder where id != selected {
            guard let session = sessions.removeValue(forKey: id) else { continue }
            verbose("\(session.name) is not a ZMK split keyboard; ignoring")
            rejected.insert(id)
            manager.cancelPeripheralConnection(session.peripheral)
        }
        sessionOrder.removeAll { sessions[$0] == nil }
        if selected == nil {
            scheduleRetry()
        }
        render()
    }

    // MARK: Output

    private func render() {
        guard config.mode == .daemon else { return }
        var levels: [Role: Int] = [:]
        if let selected, let session = sessions[selected] {
            guard session.outstanding == 0 else { return }
            if !session.roles.isEmpty {
                layout = Array(session.roles.values)
            }
            levels = session.levels
        }
        let label = formatter.label(layout: layout, levels: levels)
        guard label != lastLabel else { return }
        lastLabel = label
        verbose("label: \(label)")
        bar?.set(item: config.item, label: label)
    }

    private func finishOneShot() {
        switch config.mode {
        case .list:
            if sessionOrder.isEmpty {
                print(config.device.map { "No connected Bluetooth device matching \"\($0)\" exposes battery levels." }
                    ?? "No connected Bluetooth device exposes battery levels.")
            }
            for id in sessionOrder {
                guard let session = sessions[id] else { continue }
                let marker = id == selected ? " (selected)" : ""
                print("\(session.name) [\(id.uuidString)]\(marker)")
                let roles = formatter.order(session.roles.values)
                if roles.isEmpty { print("  no battery levels found") }
                for role in roles {
                    print("  \(role): \(session.levels[role].map { "\($0)%" } ?? "unknown")")
                }
            }
        case .once:
            let session = selected.flatMap { sessions[$0] }
            let roles = session.map { Array($0.roles.values) } ?? []
            print(formatter.label(layout: roles.isEmpty ? layout : roles, levels: session?.levels ?? [:]))
        case .daemon, .help:
            return
        }
        exit(0)
    }

    private func record(_ entry: HistoryEntry) {
        guard config.mode == .daemon else { return }
        do {
            try history.append(entry)
        } catch {
            verbose("failed to write history: \(error)")
        }
    }

    private func verbose(_ message: String) {
        if config.verbose { log(message) }
    }
}

// MARK: - CBCentralManagerDelegate

extension BatteryMonitor: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            discover()
        case .unauthorized:
            log("Bluetooth access denied. Allow it in System Settings > Privacy & Security > Bluetooth.")
            if config.mode != .daemon { exit(1) }
            render()
        case .unsupported:
            log("Bluetooth LE is not supported on this Mac.")
            exit(1)
        case .poweredOff, .resetting:
            verbose("Bluetooth is \(central.state == .poweredOff ? "off" : "resetting")")
            sessions = [:]
            sessionOrder = []
            selected = nil
            render()
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let session = session(for: peripheral) else { return }
        verbose("connected to \(session.name)")
        session.reset()
        session.outstanding += 1
        peripheral.discoverServices([GATT.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let session = session(for: peripheral) else { return }
        verbose("failed to connect to \(session.name): \(error?.localizedDescription ?? "unknown error")")
        session.outstanding = 0
        if peripheral.identifier == selected {
            central.connect(peripheral)
        }
        checkSettled()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let session = session(for: peripheral) else { return }
        verbose("\(session.name) disconnected")
        guard peripheral.identifier == selected else { return }
        record(.disconnected(device: peripheral.identifier.uuidString, at: Date()))
        session.reset()
        render()
        // Pending connects never time out: this completes when the keyboard is back.
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension BatteryMonitor: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let session = session(for: peripheral) else { return }
        session.outstanding -= 1
        if let error { verbose("\(session.name): service discovery failed: \(error.localizedDescription)") }
        for service in peripheral.services ?? [] where service.uuid == GATT.batteryService {
            session.outstanding += 1
            peripheral.discoverCharacteristics([GATT.batteryLevel], for: service)
        }
        checkSettled()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let session = session(for: peripheral) else { return }
        session.outstanding -= 1
        for characteristic in service.characteristics ?? [] where characteristic.uuid == GATT.batteryLevel {
            session.outstanding += 1
            peripheral.discoverDescriptors(for: characteristic)
        }
        checkSettled()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let session = session(for: peripheral) else { return }
        session.outstanding -= 1
        let descriptors = (characteristic.descriptors ?? []).filter {
            $0.uuid == GATT.userDescription || $0.uuid == GATT.presentationFormat
        }
        if descriptors.isEmpty {
            classify(characteristic, in: session)
        } else {
            session.pendingDescriptorReads[ObjectIdentifier(characteristic)] = descriptors.count
            for descriptor in descriptors {
                session.outstanding += 1
                peripheral.readValue(for: descriptor)
            }
        }
        checkSettled()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard let session = session(for: peripheral), let characteristic = descriptor.characteristic else { return }
        session.outstanding -= 1
        let id = ObjectIdentifier(characteristic)
        if descriptor.uuid == GATT.userDescription, let text = descriptor.value as? String {
            session.userDescriptions[id] = text
        } else if descriptor.uuid == GATT.presentationFormat, let data = descriptor.value as? Data {
            session.presentationDescriptions[id] = Classifier.presentationDescription(from: data)
        }
        let remaining = (session.pendingDescriptorReads[id] ?? 1) - 1
        session.pendingDescriptorReads[id] = remaining
        if remaining == 0 {
            classify(characteristic, in: session)
        }
        checkSettled()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let session = session(for: peripheral) else { return }
        let id = ObjectIdentifier(characteristic)
        let wasRead = session.pendingLevelReads.remove(id) != nil
        if wasRead { session.outstanding -= 1 }

        if let role = session.roles[id], let level = characteristic.value?.first {
            verbose("\(session.name): \(role) = \(level)%")
            session.levels[role] = Int(level)
            if peripheral.identifier == selected {
                record(.level(Int(level), role: role, device: peripheral.identifier.uuidString, name: session.name, at: Date()))
            }
        }
        if wasRead {
            checkSettled()
        } else {
            render()
        }
    }
}
