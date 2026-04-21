import Foundation
import Observation

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"
}

enum TreadmillCommandStatus: String {
    case idle = "Idle"
    case pending = "Pending"
    case accepted = "Accepted"
    case timedOut = "Timed Out"
    case rejected = "Rejected"
}

@Observable
class TreadmillState {
    var connectionStatus: ConnectionStatus = .disconnected
    var currentSpeed: Double = 0.0      // km/h
    var targetSpeed: Double = 0.0       // km/h
    var distance: Double = 0.0          // km
    var duration: TimeInterval = 0      // seconds
    var calories: Int = 0
    var isRunning: Bool = false
    var commandStatus: TreadmillCommandStatus = .idle
    var errorMessage: String?

    /// Steps are derived from distance (2,000 steps per mile) because treadmill
    /// adapters don't report step counts consistently — some devices return
    /// zero, some return stale odometer values, some omit the field entirely.
    var steps: Int { StepsEstimate.steps(fromKm: distance) }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedDistance: String {
        return String(format: "%.2f km", distance)
    }

    var formattedSpeed: String {
        return String(format: "%.1f km/h", currentSpeed)
    }
}
