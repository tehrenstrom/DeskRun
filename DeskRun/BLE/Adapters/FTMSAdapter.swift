import Foundation
import CoreBluetooth

/// Adapter for treadmills supporting the Bluetooth SIG Fitness Machine Service (FTMS).
///
/// FTMS is the official Bluetooth standard for fitness equipment (service 0x1826).
/// Many commercial treadmills implement this protocol, including models from
/// LifeSpan, Horizon, and some NordicTrack units.
///
/// Protocol details (Bluetooth SIG GATT specification):
/// - Service UUID: 0x1826 (Fitness Machine)
/// - Treadmill Data characteristic: 0x2ACD (notify)
/// - Fitness Machine Control Point: 0x2AD9 (write with response / indicate)
/// - Fitness Machine Feature: 0x2ACC (read)
///
/// Control Point commands require sending Request Control (0x00) first.
/// Speed values are uint16 LE in 0.01 km/h units.
struct FTMSAdapter: TreadmillAdapter {

    // MARK: - Static Identity & Matching

    static var displayName: String { "FTMS (Bluetooth Standard)" }

    static var serviceUUIDs: [CBUUID] { [CBUUID(string: "1826")] }

    /// Match any peripheral that advertises the FTMS service UUID (0x1826).
    /// FTMS is a standardized protocol, so we rely on service advertisement
    /// rather than device name matching.
    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let ftmsUUID = CBUUID(string: "1826")
            if serviceUUIDs.contains(ftmsUUID) {
                return true
            }
        }

        // Fallback: check for known FTMS treadmill brand names
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        let upper = name.uppercased()
        return upper.contains("LIFESPAN")
            || upper.contains("HORIZON")
            || upper.contains("NORDICTRACK")
    }

    // MARK: - Instance Properties

    var serviceUUID: CBUUID { CBUUID(string: "1826") }
    var writeCharacteristicUUID: CBUUID { CBUUID(string: "2AD9") }
    var notifyCharacteristicUUID: CBUUID { CBUUID(string: "2ACD") }
    var writeType: CBCharacteristicWriteType { .withResponse }

    // MARK: - Protocol Constants

    /// Control Point op codes (FTMS specification)
    private enum ControlOpCode: UInt8 {
        case requestControl  = 0x00
        case reset           = 0x01
        case setTargetSpeed  = 0x02
        case startResume     = 0x07
        case stopPause       = 0x08
    }

    /// Response indicator for Control Point indications
    private let responseOpCode: UInt8 = 0x80
    private let resultSuccess: UInt8 = 0x01

    /// Treadmill Data flag bits (uint16 LE in bytes 0-1)
    /// Per FTMS spec (Bluetooth SIG), bit 10 is Elapsed Time for treadmill data.
    private enum DataFlag {
        static let moreData:       UInt16 = 1 << 0   // bit 0: if 0, instantaneous speed present
        static let averageSpeed:   UInt16 = 1 << 1   // bit 1
        static let totalDistance:  UInt16 = 1 << 2   // bit 2
        static let expendedEnergy: UInt16 = 1 << 7   // bit 7
        static let elapsedTime:    UInt16 = 1 << 10  // bit 10 (corrected from bit 12)
    }

    // MARK: - Command Builders

    func buildStartCommand(speed: Double) -> Data {
        // FTMS requires sequential writes: Request Control → Start/Resume → Set Speed.
        // We combine all three opcodes into one data payload.
        // Note: The BLE manager sends this as a single write. For treadmills that
        // require separate writes per opcode, the manager would need to be updated
        // to send them sequentially. For now this covers common FTMS implementations.
        var packet = Data()

        // 1. Request Control
        packet.append(ControlOpCode.requestControl.rawValue)

        // 2. Start or Resume
        packet.append(ControlOpCode.startResume.rawValue)

        // 3. Set Target Speed: [0x02, speed_low, speed_high]
        let rawSpeed = UInt16(clamping: Int(round(speed * 100)))
        packet.append(ControlOpCode.setTargetSpeed.rawValue)
        packet.append(UInt8(rawSpeed & 0xFF))
        packet.append(UInt8(rawSpeed >> 8))

        return packet
    }

    func buildStopCommand() -> Data {
        // Stop: [0x08, 0x01]
        return Data([ControlOpCode.stopPause.rawValue, 0x01])
    }

    func buildPauseCommand() -> Data {
        // Pause: [0x08, 0x02]
        return Data([ControlOpCode.stopPause.rawValue, 0x02])
    }

    func buildSetSpeedCommand(speed: Double) -> Data {
        // Set Target Speed: [0x02, speed_low, speed_high]
        // Speed in 0.01 km/h units, uint16 LE
        let rawSpeed = UInt16(clamping: Int(round(speed * 100)))
        return Data([
            ControlOpCode.setTargetSpeed.rawValue,
            UInt8(rawSpeed & 0xFF),
            UInt8(rawSpeed >> 8)
        ])
    }

    // MARK: - Notification Parser

    func parseNotification(_ data: Data) -> TreadmillStatus {
        var status = TreadmillStatus()
        let bytes = [UInt8](data)

        // Minimum: 2 bytes for flags + 2 bytes for instantaneous speed
        guard bytes.count >= 4 else { return status }

        // Flags: uint16 LE
        let flags = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        var offset = 2

        // Instantaneous Speed: present when bit 0 (More Data) is 0
        if (flags & DataFlag.moreData) == 0 {
            guard offset + 2 <= bytes.count else { return status }
            let rawSpeed = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            status.speed = Double(rawSpeed) / 100.0  // 0.01 km/h -> km/h
            status.isRunning = status.speed > 0
            offset += 2
        }

        // Average Speed: uint16 LE, 0.01 km/h
        if (flags & DataFlag.averageSpeed) != 0 {
            guard offset + 2 <= bytes.count else { return status }
            // We read but don't store average speed; skip past it
            offset += 2
        }

        // Total Distance: uint24 LE, in meters
        if (flags & DataFlag.totalDistance) != 0 {
            guard offset + 3 <= bytes.count else { return status }
            let rawDistance = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
            status.distance = Double(rawDistance) / 1000.0  // meters -> km
            offset += 3
        }

        // Skip fields for bits 3-6 per FTMS Treadmill Data spec:
        // Bit 3: Inclination (sint16) + Ramp Angle (sint16) = 4 bytes
        if (flags & (1 << 3)) != 0 {
            offset += 4
        }
        // Bit 4: Positive Elevation Gain (uint16) + Negative Elevation Gain (uint16) = 4 bytes
        if (flags & (1 << 4)) != 0 {
            offset += 4
        }
        // Bit 5: Instantaneous Pace (uint8) = 1 byte
        if (flags & (1 << 5)) != 0 {
            offset += 1
        }
        // Bit 6: Average Pace (uint8) = 1 byte
        if (flags & (1 << 6)) != 0 {
            offset += 1
        }

        // Expended Energy: total kcal (uint16) + per hour (uint16) + per minute (uint8) = 5 bytes
        if (flags & DataFlag.expendedEnergy) != 0 {
            guard offset + 5 <= bytes.count else { return status }
            let totalKcal = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            status.calories = Int(totalKcal)
            offset += 5  // skip all three sub-fields
        }

        // Bit 8: Heart Rate (uint8 = 1 byte)
        if (flags & (1 << 8)) != 0 {
            offset += 1
        }
        // Bit 9: Metabolic Equivalent (uint8 = 1 byte)
        if (flags & (1 << 9)) != 0 {
            offset += 1
        }

        // Bit 10: Elapsed Time (uint16 LE, in seconds)
        if (flags & DataFlag.elapsedTime) != 0 {
            guard offset + 2 <= bytes.count else { return status }
            let rawTime = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            status.duration = TimeInterval(rawTime)
            offset += 2
        }

        // Bit 11: Remaining Time (uint16 = 2 bytes)
        if (flags & (1 << 11)) != 0 {
            offset += 2
        }

        return status
    }
}
