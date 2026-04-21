import Foundation

struct AppSettings: Codable {
    var defaultSpeed: Double = 3.0          // km/h
    var useMetric: Bool = true              // true = km, false = miles
    var notificationsEnabled: Bool = true
    var morningMotivation: Bool = true
    var goalNudges: Bool = true
    var streakAlerts: Bool = true
    var milestoneAlerts: Bool = true
    var weeklySummary: Bool = true
    var idleNudges: Bool = true
    var quietHoursStart: Int = 22           // 10 PM
    var quietHoursEnd: Int = 8              // 8 AM
    var maxNotificationsPerDay: Int = 3

    // Convenience

    func distanceString(_ km: Double) -> String {
        if useMetric {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.1f mi", km / 1.60934)
        }
    }

    func distanceValue(_ km: Double) -> Double {
        useMetric ? km : km / 1.60934
    }

    var distanceUnitShort: String {
        useMetric ? "km" : "mi"
    }
}
