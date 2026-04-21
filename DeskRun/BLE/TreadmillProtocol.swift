import Foundation
import CoreBluetooth

// MARK: - Shared Types

/// Status snapshot returned by any treadmill adapter when it parses a BLE notification.
struct TreadmillStatus {
    var speed: Double = 0.0          // km/h
    var distance: Double = 0.0       // km
    var steps: Int = 0
    var duration: TimeInterval = 0   // seconds
    var calories: Int = 0
    var isRunning: Bool = false
}

// MARK: - Treadmill Adapter Protocol

/// A protocol that every treadmill brand adapter must conform to.
///
/// The adapter encapsulates all brand-specific BLE knowledge:
/// which services/characteristics to use, how to build command packets,
/// and how to parse notification data.
///
/// **Static members** are used during scanning (before a connection exists).
/// **Instance members** are used after a peripheral has been matched and connected.
protocol TreadmillAdapter {

    /// Parameterless initializer so the registry can instantiate adapters.
    init()

    // MARK: Identity & Matching (static)

    /// Human-readable name for this adapter (e.g. "PitPat", "KingSmith WalkingPad").
    static var displayName: String { get }

    /// BLE service UUIDs to include in the scan filter.
    /// The registry unions these across all registered adapters.
    static var serviceUUIDs: [CBUUID] { get }

    /// Return `true` if the discovered peripheral belongs to this adapter.
    /// Called during scanning with the raw advertisement data.
    static func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool

    // MARK: Service & Characteristic UUIDs (instance)

    /// The primary service UUID to discover after connection.
    var serviceUUID: CBUUID { get }

    /// UUID of the characteristic used to send commands.
    var writeCharacteristicUUID: CBUUID { get }

    /// UUID of the characteristic that delivers status notifications.
    var notifyCharacteristicUUID: CBUUID { get }

    /// Write type — `.withResponse` or `.withoutResponse`.
    var writeType: CBCharacteristicWriteType { get }

    // MARK: Command Builders

    /// Build the data packet to start the treadmill at the given speed (km/h).
    func buildStartCommand(speed: Double) -> Data

    /// Build the data packet to stop the treadmill.
    func buildStopCommand() -> Data

    /// Build the data packet to pause the treadmill.
    func buildPauseCommand() -> Data

    /// Build the data packet to change speed while running (km/h).
    func buildSetSpeedCommand(speed: Double) -> Data

    // MARK: Notification Parser

    /// Parse raw notification bytes into a ``TreadmillStatus``.
    func parseNotification(_ data: Data) -> TreadmillStatus
}
