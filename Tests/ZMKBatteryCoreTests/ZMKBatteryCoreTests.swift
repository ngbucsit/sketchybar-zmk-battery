import Foundation
import Testing
@testable import ZMKBatteryCore

@Suite struct ClassifierTests {
    @Test func peripheralUserDescription() {
        #expect(Classifier.role(userDescription: "Peripheral 0", presentationDescription: nil, nextPeripheralIndex: 5) == .peripheral(0))
        #expect(Classifier.role(userDescription: "Peripheral 2\0", presentationDescription: 0x0108, nextPeripheralIndex: 0) == .peripheral(2))
    }

    @Test func auxiliaryWithoutUserDescription() {
        #expect(Classifier.role(userDescription: nil, presentationDescription: 0x0108, nextPeripheralIndex: 1) == .peripheral(1))
    }

    @Test func centralWhenUnmarked() {
        #expect(Classifier.role(userDescription: nil, presentationDescription: nil, nextPeripheralIndex: 0) == .central)
        #expect(Classifier.role(userDescription: "Battery", presentationDescription: 0x0106, nextPeripheralIndex: 0) == .central)
    }

    @Test func parsesPresentationFormat() {
        // uint8, exponent 0, unit 0x27AD (percentage), SIG namespace, description 0x0108
        let data = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x08, 0x01])
        #expect(Classifier.presentationDescription(from: data) == 0x0108)
        #expect(Classifier.presentationDescription(from: Data([0x04])) == nil)
    }
}

@Suite struct LabelFormatterTests {
    @Test func centralLeftByDefault() {
        let formatter = LabelFormatter()
        let levels: [Role: Int] = [.central: 80, .peripheral(0): 55]
        #expect(formatter.label(layout: [.peripheral(0), .central], levels: levels) == "80% | 55%")
    }

    @Test func centralRight() {
        let formatter = LabelFormatter(centralPosition: .right)
        let levels: [Role: Int] = [.central: 80, .peripheral(0): 55]
        #expect(formatter.label(layout: [.central, .peripheral(0)], levels: levels) == "55% | 80%")
    }

    @Test func manyPeripheralsKeepIndexOrder() {
        let roles: [Role] = [.peripheral(1), .central, .peripheral(0)]
        #expect(LabelFormatter().order(roles) == [.central, .peripheral(0), .peripheral(1)])
        #expect(LabelFormatter(centralPosition: .right).order(roles) == [.peripheral(0), .peripheral(1), .central])
    }

    @Test func dongleWithoutCentralBattery() {
        let formatter = LabelFormatter(centralPosition: .right)
        let levels: [Role: Int] = [.peripheral(0): 90, .peripheral(1): 70]
        #expect(formatter.label(layout: [.peripheral(1), .peripheral(0)], levels: levels) == "90% | 70%")
    }

    @Test func missingLevelsUsePlaceholder() {
        #expect(LabelFormatter().label(layout: LabelFormatter.defaultLayout, levels: [:]) == "--% | --%")
        #expect(LabelFormatter().label(layout: LabelFormatter.defaultLayout, levels: [.central: 9]) == "9% | --%")
    }

    @Test func customSeparator() {
        let formatter = LabelFormatter(separator: " ")
        #expect(formatter.label(layout: [.central, .peripheral(0)], levels: [.central: 1, .peripheral(0): 2]) == "1% 2%")
    }
}

@Suite struct ConfigTests {
    @Test func defaults() throws {
        let config = try Config.parse([])
        #expect(config == Config())
        #expect(config.mode == .daemon)
        #expect(config.item == "kb_batt")
        #expect(config.centralPosition == .left)
    }

    @Test func parsesOptions() throws {
        let config = try Config.parse(["--item", "kb", "--device=Lily58", "--central", "RIGHT", "--separator", " / ", "--list", "--verbose"])
        #expect(config.item == "kb")
        #expect(config.device == "Lily58")
        #expect(config.centralPosition == .right)
        #expect(config.separator == " / ")
        #expect(config.mode == .list)
        #expect(config.verbose)
    }

    @Test func rejectsBadInput() {
        #expect(throws: Config.ParseError.unknownOption("--nope")) { try Config.parse(["--nope"]) }
        #expect(throws: Config.ParseError.missingValue("--item")) { try Config.parse(["--item"]) }
        #expect(throws: Config.ParseError.invalidValue(option: "--central", value: "middle")) {
            try Config.parse(["--central", "middle"])
        }
    }
}
