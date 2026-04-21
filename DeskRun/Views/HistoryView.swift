import SwiftUI

struct HistoryView: View {
    let appState: AppState

    private var groupedWorkouts: [(date: Date, workouts: [WorkoutRecord])] {
        appState.workoutStore.groupedByDay
    }

    var body: some View {
        Group {
            if groupedWorkouts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedWorkouts, id: \.date) { group in
                        Section {
                            ForEach(group.workouts) { workout in
                                WorkoutRow(workout: workout, settings: appState.settings)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    appState.workoutStore.deleteWorkout(id: group.workouts[index].id)
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.date, style: .date)
                                Spacer()
                                let dayTotal = group.workouts.reduce(0.0) { $0 + $1.distance }
                                Text(appState.settings.distanceString(dayTotal))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("History")
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No workouts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your walking sessions will appear here automatically when your treadmill is connected.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let workout: WorkoutRecord
    let settings: AppSettings

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.startDate, style: .time)
                    .font(.headline)
                Text(workout.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                statLabel(settings.distanceString(workout.distance), icon: "map")
                statLabel("\(workout.steps)", icon: "shoeprints.fill")
                statLabel(String(format: "%.1f km/h", workout.averageSpeed), icon: "speedometer")
                statLabel("\(workout.calories) kcal", icon: "flame")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func statLabel(_ value: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(value)
                .monospacedDigit()
        }
    }
}
