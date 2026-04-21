import Foundation
import CoreBluetooth

/// Adapter for DeerRun / PitPat treadmills (the "4D 00 …" wire protocol).
///
/// Reverse-engineered against azmke/pitpat-treadmill-control and verified
/// byte-for-byte against a DeerRun Q2 Urban Plus (firmware 37).
///
/// Wire format:
/// - **Service UUID:** FBA0 (also seen as FF00 on some units; we only bind
///   to FBA0 here since that's what this app's registry routes to us).
/// - **Write characteristic:** FBA1 (write without response).
/// - **Notify characteristic:** FBA2.
/// - **Commands** use a 23-byte packet starting with `0x6A`, ending with
///   `0x43`, carrying speed/ramp/incline/weight/userID and an XOR checksum
///   over bytes [1..20].
/// - This `FBA0/FBA1/FBA2` variant does not require a per-notification
///   heartbeat write to keep telemetry flowing.
/// - On the `FBA0/FBA1/FBA2` service family used by DeskRun's PitPat path,
///   writes are sent directly as raw packets to `FBA1`. The older FF00-style
///   `4D 00 <counter> <len> ...` envelope seen in some references is not used
///   on this variant.
/// - **Notifications** are 52 or 53 bytes starting with `0x68` or `0x66`,
///   with an XOR checksum at `[-2]` covering `[1..-3]`.
///
/// Because the protocol requires a per-connection counter (stateful),
/// this adapter is a `final class` rather than a struct.
final class PitPatAdapter: TreadmillAdapter {

    // MARK: - Static Identity & Matching

    static var displayName: String { "DeerRun (PitPat)" }

    static var serviceUUIDs: [CBUUID] { [CBUUID(string: "FBA0")] }

    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // Primary signal: advertised service UUID FBA0. DeerRun/PitPat units
        // often ship with SKU-style names (e.g. "J-2088") that don't contain
        // "PitPat" or "DeerRun", but they still advertise the FBA0 service.
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           serviceUUIDs.contains(CBUUID(string: "FBA0")) {
            return true
        }

        // Fallback: name match for units where the service UUID isn't in the
        // advertisement packet (it may only appear after service discovery).
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        return name.contains("PitPat") || name.contains("DeerRun")
    }

    // MARK: - Instance Properties

    var serviceUUID: CBUUID { CBUUID(string: "FBA0") }
    var writeCharacteristicUUID: CBUUID { CBUUID(string: "FBA1") }
    var notifyCharacteristicUUID: CBUUID { CBUUID(string: "FBA2") }
    // FBA1 on the Q2 Urban Plus advertises properties 0x0A (read + write-with-
    // response) and rejects response-less writes with a CoreBluetooth warning,
    // so we must use .withResponse even though the azmke reference happens to
    // run on a bleak stack that auto-picks.
    var writeType: CBCharacteristicWriteType { .withResponse }
    var minimumStartSpeed: Double { 1.0 }
    var commandAcceptanceTimeout: TimeInterval { 2.0 }
    var commandAcceptanceNotificationLimit: Int { 3 }

    // MARK: - Stateful Session Data

    private var usesImperialUnits = false

    // MARK: - Protocol Constants

    private let startByte: UInt8 = 0x6A
    private let endByte: UInt8 = 0x43
    private let innerLength: UInt8 = 0x17      // 23 bytes
    private let defaultWeight: UInt8 = 0x50    // 80 kg
    private let defaultUserID: UInt64 = 58_965_456_623
    private let kilometersPerMile = 1.60934

    private enum CommandType: UInt8 {
        case stop             = 0x00
        case pause            = 0x02
        case startOrSetSpeed  = 0x04
    }

    /// Acceleration ramp time (seconds). `start` ramps gently (1s), `setSpeed`
    /// ramps faster (5s) once already running. Mirrors the reference impl.
    private enum Ramp: UInt8 {
        case start   = 1
        case setSpeed = 5
    }

    // MARK: - Init

    init() {}

    // MARK: - Command Builders

    func buildStartCommand(speed: Double) -> Data {
        buildPacket(rawSpeed: commandRawSpeed(speed),
                    ramp: .start,
                    cmd: .startOrSetSpeed,
                    isKph: true)
    }

    func buildStopCommand() -> Data {
        buildPacket(rawSpeed: 0, ramp: .start, cmd: .stop, isKph: true)
    }

    func buildPauseCommand() -> Data {
        buildPacket(rawSpeed: 0, ramp: .start, cmd: .pause, isKph: true)
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        buildPacket(rawSpeed: commandRawSpeed(speed),
                    ramp: .setSpeed,
                    cmd: .startOrSetSpeed,
                    isKph: true)
    }

    // MARK: - Keep-Alive

    func onNotificationReceived() -> Data? {
        nil
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        guard data.count >= 31 else { return status }

        let bytes = [UInt8](data)

        // Accept either SOF variant we've seen in the wild.
        guard bytes[0] == 0x66 || bytes[0] == 0x68 else { return status }

        // Length sanity (byte [1] should equal the frame size).
        let framed = Int(bytes[1])
        guard framed == data.count else { return status }

        // XOR checksum: payload[1] XOR payload[2..count-3], compared to payload[count-2].
        var cs: UInt8 = bytes[1]
        for i in 2..<(data.count - 2) { cs ^= bytes[i] }
        guard cs == bytes[data.count - 2] else { return status }

        let curSpeedRaw = (UInt16(bytes[3]) << 8) | UInt16(bytes[4])
        let targetSpeedRaw = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])

        // Running state and unit mode are encoded in the flags byte at [26].
        let flags = bytes[26]
        let usesImperialUnits = (flags & 0x80) == 0x80
        self.usesImperialUnits = usesImperialUnits
        status.pitPatStateFlags = flags
        status.pitPatUsesImperialUnits = usesImperialUnits
        status.pitPatRawCurrentSpeed = curSpeedRaw
        status.pitPatRawTargetSpeed = targetSpeedRaw

        // Speed fields are reported in the treadmill's active unit mode.
        // Normalize them to km/h for the shared app state.
        status.speed = normalizedSpeed(from: curSpeedRaw, usesImperialUnits: usesImperialUnits)
        status.reportedTargetSpeed = normalizedSpeed(from: targetSpeedRaw, usesImperialUnits: usesImperialUnits)

        // Distance is likewise reported in km or miles depending on the unit flag.
        let distRaw: UInt32 =
            (UInt32(bytes[7]) << 24) |
            (UInt32(bytes[8]) << 16) |
            (UInt32(bytes[9]) << 8)  |
            UInt32(bytes[10])
        status.distance = normalizedDistance(from: distRaw, usesImperialUnits: usesImperialUnits)

        // Calories (16-bit big-endian).
        let calRaw = (UInt16(bytes[18]) << 8) | UInt16(bytes[19])
        status.calories = Int(calRaw)

        // Duration — unit depends on firmware version at [25]:
        // fw > 19 → milliseconds; else → seconds.
        let durRaw: UInt32 =
            (UInt32(bytes[20]) << 24) |
            (UInt32(bytes[21]) << 16) |
            (UInt32(bytes[22]) << 8)  |
            UInt32(bytes[23])
        let firmwareVersion = bytes[25]
        status.pitPatFirmwareVersion = firmwareVersion
        status.duration = firmwareVersion > 19
            ? TimeInterval(durRaw) / 1000.0
            : TimeInterval(durRaw)

        // Running state: flags byte at [26] encodes state in bits 3-4 (0x18).
        // 0x08 means "running"; everything else (stopped, paused, finished) we
        // treat as not-running. Also fall back to speed>0 for robustness.
        let stateBits = flags & 0x18
        status.isRunning = (stateBits == 0x08) || status.speed > 0

        return status
    }

    // MARK: - Private Helpers

    /// Outgoing FBA control packets are encoded in km/h on this PitPat family,
    /// even when status notifications report imperial units.
    private func commandRawSpeed(_ speed: Double) -> UInt16 {
        let raw = Int((speed * 1000.0).rounded())
        return UInt16(clamping: max(0, raw))
    }

    private func normalizedSpeed(from rawSpeed: UInt16, usesImperialUnits: Bool) -> Double {
        let baseSpeed = Double(rawSpeed) / 1000.0
        return usesImperialUnits ? baseSpeed * kilometersPerMile : baseSpeed
    }

    private func normalizedDistance(from rawDistance: UInt32, usesImperialUnits: Bool) -> Double {
        let baseDistance = Double(rawDistance) / 1000.0
        return usesImperialUnits ? baseDistance * kilometersPerMile : baseDistance
    }

    /// Build the 23-byte FBA command packet.
    private func buildPacket(rawSpeed: UInt16,
                             ramp: Ramp,
                             cmd: CommandType,
                             incline: UInt8 = 0,
                             isKph: Bool = true) -> Data {
        var p = [UInt8](repeating: 0, count: 23)
        p[0] = startByte
        p[1] = innerLength
        // p[2..5] stay zero.
        p[6] = UInt8((rawSpeed >> 8) & 0xFF)
        p[7] = UInt8(rawSpeed & 0xFF)
        p[8] = ramp.rawValue
        p[9] = incline
        p[10] = defaultWeight
        p[11] = 0
        // Unit bit: kph clears 0x08, mph sets it.
        p[12] = isKph ? (cmd.rawValue & 0xF7) : (cmd.rawValue | 0x08)
        // 8-byte big-endian user ID.
        for i in 0..<8 {
            p[13 + i] = UInt8((defaultUserID >> UInt64(56 - i * 8)) & 0xFF)
        }
        // XOR checksum over bytes [1..20] inclusive.
        var cs: UInt8 = 0
        for i in 1...20 { cs ^= p[i] }
        p[21] = cs
        p[22] = endByte
        return Data(p)
    }
}
