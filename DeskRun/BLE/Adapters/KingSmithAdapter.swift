import Foundation
import CoreBluetooth

/// Adapter for KingSmith WalkingPad treadmills.
///
/// Protocol reverse-engineered from ph4r05/walkingpad and QWalkingPad:
/// - Service UUID: FE00
/// - Write characteristic: FE01
/// - Notify characteristic: FE02
/// - Packets framed with 0xF7 (commands) or 0xF8 (status notifications) … 0xFD (end)
/// - Command checksum: additive — sum(payload) % 256
/// - Status checksum: XOR of payload bytes
/// - Control packets use 6-byte A2 key/value format
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

    private let commandStartMarker: UInt8 = 0xF7
    private let statusStartMarker: UInt8 = 0xF8
    private let endMarker: UInt8 = 0xFD

    /// Command categories
    private enum Category: UInt8 {
        case treadmillControl = 0xA2
        case queryStatus     = 0xA6
        case settings        = 0xA7
    }

    /// Control keys for 6-byte A2 key/value commands
    private enum ControlKey: UInt8 {
        case startBelt  = 0x01  // value: 1 = start, 0 = stop
        case setSpeed   = 0x02  // value: speed in 0.1 km/h
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
        // Send start command, then set speed
        var packet = buildControlPacket(key: .startBelt, value: 0x01)
        if speedByte > 0 {
            packet.append(contentsOf: buildControlPacket(key: .setSpeed, value: speedByte))
        }
        return packet
    }

    func buildStopCommand() -> Data {
        return buildControlPacket(key: .startBelt, value: 0x00)
    }

    func buildPauseCommand() -> Data {
        // WalkingPad has no distinct pause — sending stop pauses the belt.
        return buildStopCommand()
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        let speedByte = speedToRaw(speed)
        return buildControlPacket(key: .setSpeed, value: speedByte)
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        let bytes = [UInt8](data)

        // Status packets are framed with 0xF8 (not 0xF7 which is for commands).
        // Accept both 0xF7 and 0xF8 start markers for robustness.
        guard bytes.count >= 13,
              (bytes.first == statusStartMarker || bytes.first == commandStartMarker),
              bytes.last == endMarker else {
            return status
        }

        // Verify checksum: XOR of all payload bytes (between start and end markers)
        let payload = Array(bytes[1..<(bytes.count - 2)])  // exclude start, checksum, end
        let expectedChecksum = bytes[bytes.count - 2]
        var computed: UInt8 = 0
        for b in payload { computed ^= b }
        guard computed == expectedChecksum else { return status }

        // Parse A2 status fields
        // [0]=start, [1]=0xA2, [2]=state, [3]=speed, [4]=mode,
        // [5..7]=time (3-byte BE), [8..10]=distance (3-byte BE),
        // [11..13]=steps (3-byte BE), …, [n-2]=checksum, [n-1]=0xFD
        guard bytes[1] == Category.treadmillControl.rawValue else { return status }

        let state = bytes[2]
        status.isRunning = (state == RunState.running.rawValue)

        // Speed in 0.1 km/h units
        status.speed = Double(bytes[3]) / 10.0

        // Duration: 3-byte big-endian counter (total seconds)
        if bytes.count >= 8 {
            let rawTime = (UInt32(bytes[5]) << 16) | (UInt32(bytes[6]) << 8) | UInt32(bytes[7])
            status.duration = TimeInterval(rawTime)
        }

        // Distance: 3-byte big-endian counter (in 10 m units → km)
        if bytes.count >= 11 {
            let rawDistance = (UInt32(bytes[8]) << 16) | (UInt32(bytes[9]) << 8) | UInt32(bytes[10])
            status.distance = Double(rawDistance) * 10.0 / 1000.0  // 10 m → km
        }

        // WalkingPad doesn't report calories in the base notification;
        // leave at default 0.

        return status
    }

    // MARK: - Private Helpers

    /// Convert km/h to the WalkingPad raw speed byte (0.1 km/h units).
    private func speedToRaw(_ kmh: Double) -> UInt8 {
        return UInt8(clamping: Int(round(kmh * 10)))
    }

    /// Build a 6-byte A2 key/value control packet with additive checksum:
    /// `[0xF7, 0xA2, key, value, checksum, 0xFD]`
    /// Checksum = sum of bytes between start and end markers (exclusive), mod 256.
    private func buildControlPacket(key: ControlKey, value: UInt8) -> Data {
        let payload: [UInt8] = [
            Category.treadmillControl.rawValue,  // 0xA2
            key.rawValue,
            value
        ]
        let checksum = UInt8(payload.reduce(0) { ($0 + UInt16($1)) } % 256)
        var packet: [UInt8] = [commandStartMarker]
        packet.append(contentsOf: payload)
        packet.append(checksum)
        packet.append(endMarker)
        return Data(packet)
    }
}
