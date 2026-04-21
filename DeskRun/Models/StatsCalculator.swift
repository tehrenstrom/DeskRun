import Foundation
import Observation

struct PeriodStats {
    var distance: Double = 0      // km
    var duration: TimeInterval = 0
    var steps: Int = 0
    var calories: Int = 0
    var workoutCount: Int = 0

    var averageSpeed: Double {
        guard duration > 0 else { return 0 }
        return distance / (duration / 3600)
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

enum StatsPeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All Time"
}

struct DailyDistance: Identifiable {
    let id: Date
    let date: Date
    let distance: Double  // km

    init(date: Date, distance: Double) {
        self.id = date
        self.date = date
        self.distance = distance
    }
}

@Observable
class StatsCalculator {
    private let workoutStore: WorkoutStore

    init(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
    }

    // MARK: - Period Stats

    func stats(for period: StatsPeriod) -> PeriodStats {
        let workouts = workoutsFor(period: period)
        return aggregate(workouts)
    }

    var todayStats: PeriodStats {
        aggregate(workoutStore.todaysWorkouts)
    }

    // MARK: - Streaks

    var currentStreak: Int {
        calculateStreak(current: true)
    }

    var bestStreak: Int {
        calculateStreak(current: false)
    }

    // MARK: - Daily Distance Chart Data

    func dailyDistances(last days: Int) -> [DailyDistance] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [DailyDistance] = []

        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayWorkouts = workoutStore.workouts(for: date)
            let totalDistance = dayWorkouts.reduce(0.0) { $0 + $1.distance }
            result.append(DailyDistance(date: date, distance: totalDistance))
        }
        return result
    }

    // MARK: - Today's Progress

    func todayProgress(target: Double, unit: GoalUnit) -> Double {
        let today = todayStats
        switch unit {
        case .miles: return (today.distance / 1.60934) / target
        case .km: return today.distance / target
        case .minutes: return (today.duration / 60) / target
        case .hours: return (today.duration / 3600) / target
        case .steps: return Double(today.steps) / target
        }
    }

    // MARK: - Private

    private func workoutsFor(period: StatsPeriod) -> [WorkoutRecord] {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .day:
            return workoutStore.todaysWorkouts
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return workoutStore.workouts.filter { $0.startDate >= start }
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return workoutStore.workouts.filter { $0.startDate >= start }
        case .year:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return workoutStore.workouts.filter { $0.startDate >= start }
        case .allTime:
            return workoutStore.workouts
        }
    }

    private func aggregate(_ workouts: [WorkoutRecord]) -> PeriodStats {
        var stats = PeriodStats()
        stats.workoutCount = workouts.count
        for w in workouts {
            stats.distance += w.distance
            stats.duration += w.duration
            stats.steps += w.steps
            stats.calories += w.calories
        }
        return stats
    }

    private func calculateStreak(current: Bool) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get all unique days with activity, sorted descending
        let activeDays = Set(workoutStore.workouts.map { calendar.startOfDay(for: $0.startDate) })
            .sorted(by: >)

        guard !activeDays.isEmpty else { return 0 }

        if current {
            // Current streak: must include today or yesterday
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            guard activeDays.first == today || activeDays.first == yesterday else { return 0 }

            var streak = 0
            var checkDate = activeDays.contains(today) ? today : yesterday

            while activeDays.contains(checkDate) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            }
            return streak
        } else {
            // Best streak ever
            var best = 0
            var currentRun = 1

            for i in 1..<activeDays.count {
                let diff = calendar.dateComponents([.day], from: activeDays[i], to: activeDays[i - 1]).day ?? 0
                if diff == 1 {
                    currentRun += 1
                } else {
                    best = max(best, currentRun)
                    currentRun = 1
                }
            }
            return max(best, currentRun)
        }
    }
}
