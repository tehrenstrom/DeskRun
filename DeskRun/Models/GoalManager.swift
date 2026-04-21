import Foundation
import Observation

@Observable
class GoalManager {
    var goals: [Goal] = []
    private let dataManager: DataManager

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.goals = dataManager.loadGoals()
    }

    // MARK: - CRUD

    func addGoal(_ goal: Goal) {
        goals.append(goal)
        save()
    }

    func updateGoal(_ goal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
            save()
        }
    }

    func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        save()
    }

    func toggleGoal(id: UUID) {
        if let index = goals.firstIndex(where: { $0.id == id }) {
            goals[index].isActive.toggle()
            save()
        }
    }

    // MARK: - Active Goals

    var activeGoals: [Goal] {
        goals.filter { $0.isActive }
    }

    var primaryGoal: Goal? {
        activeGoals.first
    }

    // MARK: - Progress Calculation

    func progress(for goal: Goal, workouts: [WorkoutRecord], settings: AppSettings) -> GoalProgress {
        let relevantWorkouts = workoutsInTimeframe(for: goal, from: workouts)
        let current = accumulatedValue(for: goal, workouts: relevantWorkouts, settings: settings)
        let percentage = min(current / goal.target, 1.0)
        let remaining = max(goal.target - current, 0)

        return GoalProgress(
            goal: goal,
            currentValue: current,
            percentage: percentage,
            remaining: remaining
        )
    }

    // MARK: - Journey Goal Helpers

    func createJourneyGoal(from preset: JourneyPreset, useMetric: Bool, months: Int = 4) -> Goal {
        let distance = useMetric ? preset.distanceKm : preset.distanceMiles
        let unit: GoalUnit = useMetric ? .km : .miles
        let endDate = Calendar.current.date(byAdding: .month, value: months, to: Date())

        return Goal(
            name: preset.name,
            type: .distance,
            target: distance,
            unit: unit,
            timeframe: .custom,
            startDate: Date(),
            endDate: endDate,
            isActive: true
        )
    }

    // MARK: - Nudge Text

    func nudgeText(for goal: Goal, workouts: [WorkoutRecord], settings: AppSettings) -> String? {
        let prog = progress(for: goal, workouts: workouts, settings: settings)
        guard prog.percentage < 1.0 else { return nil }

        let remaining = prog.remaining
        let unit = goal.unit.symbol

        switch goal.timeframe {
        case .daily:
            let minutesNeeded = Int(remaining / 0.08) // ~5 km/h ≈ 0.08 km/min
            if minutesNeeded <= 60 {
                return "A \(minutesNeeded) min walk would hit your goal"
            } else {
                return "\(String(format: "%.1f", remaining)) \(unit) left today"
            }
        case .custom:
            // Journey goal — show pace needed
            guard let endDate = goal.endDate else { return nil }
            let daysRemaining = max(Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 1, 1)
            let paceNeeded = remaining / Double(daysRemaining)
            return "Average \(String(format: "%.1f", paceNeeded)) \(unit)/day to finish on time"
        default:
            return "\(String(format: "%.1f", remaining)) \(unit) remaining this \(goal.timeframe.displayName.lowercased()) period"
        }
    }

    // MARK: - Private

    private func workoutsInTimeframe(for goal: Goal, from workouts: [WorkoutRecord]) -> [WorkoutRecord] {
        let calendar = Calendar.current
        let now = Date()

        switch goal.timeframe {
        case .daily:
            return workouts.filter { calendar.isDateInToday($0.startDate) }
        case .weekly:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return workouts.filter { $0.startDate >= startOfWeek }
        case .monthly:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return workouts.filter { $0.startDate >= startOfMonth }
        case .yearly:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return workouts.filter { $0.startDate >= startOfYear }
        case .custom:
            return workouts.filter { $0.startDate >= goal.startDate }
        }
    }

    private func accumulatedValue(for goal: Goal, workouts: [WorkoutRecord], settings: AppSettings) -> Double {
        switch goal.type {
        case .distance:
            let totalKm = workouts.reduce(0.0) { $0 + $1.distance }
            return goal.unit == .miles ? totalKm / 1.60934 : totalKm
        case .time:
            let totalSeconds = workouts.reduce(0.0) { $0 + $1.duration }
            return goal.unit == .hours ? totalSeconds / 3600 : totalSeconds / 60
        case .steps:
            return Double(workouts.reduce(0) { $0 + $1.steps })
        }
    }

    private func save() {
        dataManager.saveGoals(goals)
    }
}

// MARK: - GoalProgress

struct GoalProgress {
    let goal: Goal
    let currentValue: Double
    let percentage: Double
    let remaining: Double

    var formattedCurrent: String {
        String(format: "%.1f", currentValue)
    }

    var formattedTarget: String {
        String(format: "%.1f", goal.target)
    }

    var percentageInt: Int {
        Int(percentage * 100)
    }
}
