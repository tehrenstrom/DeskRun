import Foundation
import CoreBluetooth

/// Adapter for DeerRun / PitPat treadmills.
///
/// Protocol details:
/// - Service UUID: FBA0
/// - Write characteristic: FBA1 (write without response)
/// - Notify characteristic: FBA2
/// - Packet length: 23 bytes, XOR checksum in last byte
/// - Start byte: 0x6A
struct PitPatAdapter: TreadmillAdapter {

    // MARK: - Static Identity & Matching

    static var displayName: String { "DeerRun (PitPat)" }

    static var serviceUUIDs: [CBUUID] { [CBUUID(string: "FBA0")] }

    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        return name.contains("PitPat") || name.contains("DeerRun")
    }

    // MARK: - Instance Properties

    var serviceUUID: CBUUID { CBUUID(string: "FBA0") }
    var writeCharacteristicUUID: CBUUID { CBUUID(string: "FBA1") }
    var notifyCharacteristicUUID: CBUUID { CBUUID(string: "FBA2") }
    var writeType: CBCharacteristicWriteType { .withoutResponse }

    // MARK: - Protocol Constants

    private let startByte: UInt8 = 0x6A
    private let packetLength = 23

    private enum CommandType: UInt8 {
        case stop = 0x00
        case pause = 0x02
        case startOrSetSpeed = 0x04
    }

    private enum NotificationOffsets {
        static let startByte = 0
        static let stateIndicator = 1
        static let speedHigh = 2
        static let speedLow = 3
        static let distanceStart = 4    // 4 bytes
        static let stepsHigh = 8
        static let stepsLow = 9
        static let durationHigh = 10
        static let durationLow = 11
        static let caloriesHigh = 12
        static let caloriesLow = 13
    }

    // MARK: - Command Builders

    func buildStartCommand(speed: Double) -> Data {
        return buildSpeedPacket(speed: speed)
    }

    func buildStopCommand() -> Data {
        return buildPacket(command: .stop)
    }

    func buildPauseCommand() -> Data {
        return buildPacket(command: .pause)
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        return buildSpeedPacket(speed: speed)
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        guard data.count >= 14 else { return status }

        let bytes = [UInt8](data)

        // Verify start byte
        guard bytes[NotificationOffsets.startByte] == startByte else { return status }

        // Speed (divide by 10 for km/h)
        let rawSpeed = (UInt16(bytes[NotificationOffsets.speedHigh]) << 8)
            | UInt16(bytes[NotificationOffsets.speedLow])
        status.speed = Double(rawSpeed) / 10.0

        // Distance (4 bytes, centimeters → km)
        var rawDistance: UInt32 = 0
        for i in 0..<4 {
            rawDistance = (rawDistance << 8) | UInt32(bytes[NotificationOffsets.distanceStart + i])
        }
        status.distance = Double(rawDistance) / 100.0

        // Steps
        let rawSteps = (UInt16(bytes[NotificationOffsets.stepsHigh]) << 8)
            | UInt16(bytes[NotificationOffsets.stepsLow])
        status.steps = Int(rawSteps)

        // Duration in seconds
        let rawDuration = (UInt16(bytes[NotificationOffsets.durationHigh]) << 8)
            | UInt16(bytes[NotificationOffsets.durationLow])
        status.duration = TimeInterval(rawDuration)

        // Calories
        let rawCalories = (UInt16(bytes[NotificationOffsets.caloriesHigh]) << 8)
            | UInt16(bytes[NotificationOffsets.caloriesLow])
        status.calories = Int(rawCalories)

        // Running state
        status.isRunning = status.speed > 0

        return status
    }

    // MARK: - Private Helpers

    private func buildSpeedPacket(speed: Double) -> Data {
        var packet = [UInt8](repeating: 0, count: packetLength)
        packet[0] = startByte
        packet[1] = CommandType.startOrSetSpeed.rawValue

        let speedValue = UInt16(speed * 10)
        packet[2] = UInt8(speedValue >> 8)
        packet[3] = UInt8(speedValue & 0xFF)

        packet[packetLength - 1] = xorChecksum(packet)
        return Data(packet)
    }

    private func buildPacket(command: CommandType) -> Data {
        var packet = [UInt8](repeating: 0, count: packetLength)
        packet[0] = startByte
        packet[1] = command.rawValue

        packet[packetLength - 1] = xorChecksum(packet)
        return Data(packet)
    }

    private func xorChecksum(_ packet: [UInt8]) -> UInt8 {
        var checksum: UInt8 = 0
        for i in 0..<(packet.count - 1) {
            checksum ^= packet[i]
        }
        return checksum
    }
}
