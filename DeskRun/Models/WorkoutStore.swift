import Foundation
import Observation

@Observable
class WorkoutStore {
    var workouts: [WorkoutRecord] = []
    private let dataManager: DataManager

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        self.workouts = dataManager.loadWorkouts()
        backfillLegacyStepsIfNeeded()
    }

    /// Records saved before we derived steps from distance have `steps == 0`
    /// because the treadmill didn't report steps. Populate them from distance
    /// so History and stats show a realistic count. Idempotent: once a record
    /// has non-zero steps it's left alone.
    private func backfillLegacyStepsIfNeeded() {
        var didChange = false
        for i in workouts.indices {
            if workouts[i].steps == 0 && workouts[i].distance > 0 {
                workouts[i].steps = StepsEstimate.steps(fromKm: workouts[i].distance)
                didChange = true
            }
        }
        if didChange { save() }
    }

    // MARK: - CRUD

    func addWorkout(_ workout: WorkoutRecord) {
        workouts.append(workout)
        workouts.sort { $0.startDate > $1.startDate }
        save()
    }

    func deleteWorkout(id: UUID) {
        workouts.removeAll { $0.id == id }
        save()
    }

    func replaceWorkouts(_ workouts: [WorkoutRecord]) {
        self.workouts = workouts.sorted { $0.startDate > $1.startDate }
        save()
    }

    // MARK: - Queries

    var todaysWorkouts: [WorkoutRecord] {
        let calendar = Calendar.current
        return workouts.filter { calendar.isDateInToday($0.startDate) }
    }

    func workouts(for date: Date) -> [WorkoutRecord] {
        let calendar = Calendar.current
        return workouts.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
    }

    func workouts(in range: ClosedRange<Date>) -> [WorkoutRecord] {
        workouts.filter { range.contains($0.startDate) }
    }

    /// Workouts grouped by day, sorted newest first
    var groupedByDay: [(date: Date, workouts: [WorkoutRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: workouts) { workout in
            calendar.startOfDay(for: workout.startDate)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, workouts: $0.value) }
    }

    private func save() {
        dataManager.saveWorkouts(workouts)
    }
}
