import Foundation
import CoreBluetooth

/// Adapter for treadmills using the FitShow / Merach BLE protocol.
///
/// This covers a wide range of budget treadmills sold under many brand names:
/// UREVO, Goplus/SuperFit, REDLIRO, Costway, UMAY, Sperax, Egofit, AIRHOT,
/// and other devices whose BLE names start with "FS-", "SW", "MERACH-", "DB-",
/// "XQIAO-", "YUNZHIDONG-", or "YOUHUO-".
///
/// Protocol details (derived from qdomyos-zwift):
/// - Service UUID: 0xFFF0
/// - Write characteristic: 0xFFF2 (write without response)
/// - Notify characteristic: 0xFFF1
///
/// Packet format:
/// - Header: [0x02, length_byte]
/// - Payload bytes
/// - Checksum: XOR of all preceding bytes
///
/// Note: The exact byte layout varies across FitShow firmware versions.
/// All offsets are defined as named constants so they can be adjusted per-model
/// if needed in the future.
struct FitShowAdapter: TreadmillAdapter {

    // MARK: - Static Identity & Matching

    static var displayName: String { "FitShow (UREVO, Goplus, REDLIRO, Costway, UMAY)" }

    static var serviceUUIDs: [CBUUID] { [CBUUID(string: "FFF0")] }

    /// Match peripherals by device name prefixes/substrings used across
    /// FitShow-based treadmill brands.
    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        let upper = name.uppercased()

        // Protocol-specific prefixes
        let prefixes = ["FS-", "SW", "MERACH-", "DB-", "XQIAO-", "YUNZHIDONG-", "YOUHUO-"]
        for prefix in prefixes {
            if upper.hasPrefix(prefix) { return true }
        }

        // Brand-name substrings
        let brands = ["UREVO", "GOPLUS", "SUPERFIT", "REDLIRO", "COSTWAY",
                       "UMAY", "SPERAX", "EGOFIT", "AIRHOT"]
        for brand in brands {
            if upper.contains(brand) { return true }
        }

        return false
    }

    // MARK: - Instance Properties

    var serviceUUID: CBUUID { CBUUID(string: "FFF0") }
    var writeCharacteristicUUID: CBUUID { CBUUID(string: "FFF2") }
    var notifyCharacteristicUUID: CBUUID { CBUUID(string: "FFF1") }
    var writeType: CBCharacteristicWriteType { .withoutResponse }

    // MARK: - Protocol Constants

    /// Standard FitShow packet header byte.
    private let headerByte: UInt8 = 0x02

    /// Command identifiers sent in the payload.
    private enum Command {
        /// Start or change speed: [header, 0x04, 0x01, speed_byte, checksum]
        static let startOrSetSpeed: UInt8 = 0x04
        /// Stop: [header, 0x04, 0x02, 0x00, checksum]
        static let stopOrPause: UInt8 = 0x04
        /// Query status: [header, 0x02, 0x00, checksum]
        static let queryStatus: UInt8 = 0x02
    }

    /// Sub-command bytes within a command packet.
    private enum SubCommand {
        static let start: UInt8 = 0x01       // also used for set-speed
        static let stop: UInt8 = 0x02
    }

    /// Byte offsets within a status notification.
    /// These are the most common layout; some firmware versions differ slightly.
    private enum NotifyOffset {
        static let header       = 0   // 0x02
        static let length       = 1
        static let commandType  = 2   // state indicator
        static let speedByte    = 3   // value / 10.0 = km/h
        static let distanceHigh = 4   // uint16 — units vary by model
        static let distanceLow  = 5
        static let timeHigh     = 6   // uint16, seconds
        static let timeLow      = 7
        static let caloriesHigh = 8   // uint16
        static let caloriesLow  = 9
        static let stepsHigh    = 10  // may not be present on all models
        static let stepsLow     = 11
    }

    /// Minimum notification length required to parse core fields
    /// (header + length + command + speed + distance + time + calories = 10 bytes).
    private let minNotifyLength = 10

    // MARK: - Command Builders

    func buildStartCommand(speed: Double) -> Data {
        return buildSpeedCommand(speed: speed)
    }

    func buildStopCommand() -> Data {
        // [header, 0x04, 0x02, 0x00, checksum]
        var packet: [UInt8] = [headerByte, Command.stopOrPause, SubCommand.stop, 0x00]
        packet.append(xorChecksum(packet))
        return Data(packet)
    }

    func buildPauseCommand() -> Data {
        // FitShow uses the same stop command for pause on most models.
        return buildStopCommand()
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        return buildSpeedCommand(speed: speed)
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        let bytes = [UInt8](data)

        guard bytes.count >= minNotifyLength else { return status }

        // Verify header byte (accept both 0x02 and 0xF7 variants)
        let header = bytes[NotifyOffset.header]
        guard header == 0x02 || header == 0xF7 else { return status }

        // Speed: single byte, value / 10.0 = km/h
        let rawSpeed = bytes[NotifyOffset.speedByte]
        status.speed = Double(rawSpeed) / 10.0

        // Distance: uint16 big-endian, in 10-meter units (0.01 km).
        // Some models use 100m units — callers can adjust if needed.
        let rawDistance = (UInt16(bytes[NotifyOffset.distanceHigh]) << 8)
            | UInt16(bytes[NotifyOffset.distanceLow])
        status.distance = Double(rawDistance) / 100.0  // 10m units → km

        // Elapsed time: uint16 big-endian, in seconds
        let rawTime = (UInt16(bytes[NotifyOffset.timeHigh]) << 8)
            | UInt16(bytes[NotifyOffset.timeLow])
        status.duration = TimeInterval(rawTime)

        // Calories: uint16 big-endian
        let rawCalories = (UInt16(bytes[NotifyOffset.caloriesHigh]) << 8)
            | UInt16(bytes[NotifyOffset.caloriesLow])
        status.calories = Int(rawCalories)

        // Steps: optional, only present if packet is long enough
        if bytes.count >= NotifyOffset.stepsLow + 1 {
            let rawSteps = (UInt16(bytes[NotifyOffset.stepsHigh]) << 8)
                | UInt16(bytes[NotifyOffset.stepsLow])
            status.steps = Int(rawSteps)
        }

        // Running state
        status.isRunning = status.speed > 0

        return status
    }

    // MARK: - Private Helpers

    /// Build a start/set-speed packet: [header, 0x04, 0x01, speed_byte, checksum]
    /// where speed_byte = speed * 10 (e.g., 3.0 km/h → 30).
    private func buildSpeedCommand(speed: Double) -> Data {
        let speedByte = UInt8(clamping: Int(round(speed * 10)))
        var packet: [UInt8] = [headerByte, Command.startOrSetSpeed, SubCommand.start, speedByte]
        packet.append(xorChecksum(packet))
        return Data(packet)
    }

    /// XOR all bytes to produce a single checksum byte.
    private func xorChecksum(_ bytes: [UInt8]) -> UInt8 {
        var checksum: UInt8 = 0
        for byte in bytes {
            checksum ^= byte
        }
        return checksum
    }
}
