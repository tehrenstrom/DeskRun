import Foundation
import CoreBluetooth

/// Adapter for KingSmith WalkingPad treadmills.
///
/// Protocol reverse-engineered from ph4r05/walkingpad and QWalkingPad:
/// - Service UUID: FE00
/// - Write characteristic: FE01
/// - Notify characteristic: FE02
/// - Packets framed with 0xF7 (start) … 0xFD (end)
/// - Checksum: XOR of all bytes between start and end markers (exclusive)
struct KingSmithAdapter: TreadmillAdapter {

    // MARK: - Static Identity & Matching

    static var displayName: String { "KingSmith WalkingPad" }

    static var serviceUUIDs: [CBUUID] { [CBUUID(string: "FE00")] }

    /// Match peripherals whose advertised name contains any known KingSmith identifier.
    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        let upper = name.uppercased()
        return upper.contains("WALKINGPAD")
            || upper.contains("KS-")
            || upper == "R1" || upper.hasPrefix("R1 ") || upper.hasSuffix(" R1")
            || upper == "R2" || upper.hasPrefix("R2 ") || upper.hasSuffix(" R2")
            || upper == "A1" || upper.hasPrefix("A1 ") || upper.hasSuffix(" A1")
            || upper == "C2" || upper.hasPrefix("C2 ") || upper.hasSuffix(" C2")
    }

    // MARK: - Instance Properties

    var serviceUUID: CBUUID { CBUUID(string: "FE00") }
    var writeCharacteristicUUID: CBUUID { CBUUID(string: "FE01") }
    var notifyCharacteristicUUID: CBUUID { CBUUID(string: "FE02") }
    var writeType: CBCharacteristicWriteType { .withoutResponse }

    // MARK: - Protocol Constants

    private let startMarker: UInt8 = 0xF7
    private let endMarker: UInt8 = 0xFD

    /// Command categories
    private enum Category: UInt8 {
        case treadmillControl = 0xA2
        case queryStatus     = 0xA6
        case settings        = 0xA7
    }

    /// State byte values in notifications
    private enum RunState: UInt8 {
        case idle    = 0
        case running = 1
        case standby = 2
    }

    // MARK: - Command Builders

    func buildStartCommand(speed: Double) -> Data {
        let speedByte = speedToRaw(speed)
        return buildControlPacket(running: true, speed: speedByte)
    }

    func buildStopCommand() -> Data {
        return buildControlPacket(running: false, speed: 0)
    }

    func buildPauseCommand() -> Data {
        // WalkingPad has no distinct pause — sending stop with speed 0 pauses the belt.
        return buildStopCommand()
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        let speedByte = speedToRaw(speed)
        return buildControlPacket(running: true, speed: speedByte)
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        let bytes = [UInt8](data)

        // Minimum viable status packet: start + category + state + speed + mode +
        // time_min + time_sec + dist_hi + dist_lo + steps_hi + steps_lo + checksum + end = 13
        guard bytes.count >= 13,
              bytes.first == startMarker,
              bytes.last == endMarker else {
            return status
        }

        // Verify checksum: XOR of all payload bytes (between start and end markers)
        let payload = Array(bytes[1..<(bytes.count - 2)])  // exclude start, checksum, end
        let expectedChecksum = bytes[bytes.count - 2]
        var computed: UInt8 = 0
        for b in payload { computed ^= b }
        guard computed == expectedChecksum else { return status }

        // Parse fields (offsets relative to full packet)
        // [0]=0xF7, [1]=0xA2, [2]=state, [3]=speed, [4]=mode,
        // [5]=time_min, [6]=time_sec, [7]=dist_hi, [8]=dist_lo,
        // [9]=steps_hi, [10]=steps_lo, …, [n-2]=checksum, [n-1]=0xFD
        guard bytes[1] == Category.treadmillControl.rawValue else { return status }

        let state = bytes[2]
        status.isRunning = (state == RunState.running.rawValue)

        // Speed in 0.1 km/h units
        status.speed = Double(bytes[3]) / 10.0

        // Duration: minutes + seconds
        let minutes = Int(bytes[5])
        let seconds = Int(bytes[6])
        status.duration = TimeInterval(minutes * 60 + seconds)

        // Distance: uint16 in 10 m units → km
        let rawDistance = (UInt16(bytes[7]) << 8) | UInt16(bytes[8])
        status.distance = Double(rawDistance) * 10.0 / 1000.0  // 10 m → km

        // Steps: uint16
        let rawSteps = (UInt16(bytes[9]) << 8) | UInt16(bytes[10])
        status.steps = Int(rawSteps)

        // WalkingPad doesn't report calories in the base notification;
        // leave at default 0.

        return status
    }

    // MARK: - Private Helpers

    /// Convert km/h to the WalkingPad raw speed byte (0.1 km/h units).
    private func speedToRaw(_ kmh: Double) -> UInt8 {
        return UInt8(clamping: Int(round(kmh * 10)))
    }

    /// Build a treadmill-control packet:
    /// `[0xF7, 0xA2, 0x01, runFlag, speed, checksum, 0xFD]`
    private func buildControlPacket(running: Bool, speed: UInt8) -> Data {
        let runFlag: UInt8 = running ? 0x01 : 0x00
        let payload: [UInt8] = [
            Category.treadmillControl.rawValue,  // 0xA2
            0x01,                                 // sub-command: belt control
            runFlag,
            speed
        ]
        let checksum = payload.reduce(UInt8(0), ^)
        var packet: [UInt8] = [startMarker]
        packet.append(contentsOf: payload)
        packet.append(checksum)
        packet.append(endMarker)
        return Data(packet)
    }
}
