import SwiftUI

struct GoalsView: View {
    let appState: AppState
    @State private var showingAddGoal = false
    @State private var showingJourneyPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Your Goals")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Menu {
                        Button("New Daily Goal") { showingAddGoal = true }
                        Button("Start a Journey") { showingJourneyPicker = true }
                    } label: {
                        Label("Add Goal", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Active Goals
                if appState.goalManager.activeGoals.isEmpty {
                    emptyState
                } else {
                    ForEach(appState.goalManager.activeGoals) { goal in
                        GoalCard(goal: goal, appState: appState)
                    }
                }

                // Inactive goals
                let inactive = appState.goalManager.goals.filter { !$0.isActive }
                if !inactive.isEmpty {
                    Text("Inactive")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ForEach(inactive) { goal in
                        GoalCard(goal: goal, appState: appState)
                            .opacity(0.6)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Goals")
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet(appState: appState)
        }
        .sheet(isPresented: $showingJourneyPicker) {
            JourneyPickerSheet(appState: appState)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No active goals")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Set a daily distance goal or start a journey to track your progress.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - GoalCard

struct GoalCard: View {
    let goal: Goal
    let appState: AppState

    private var progress: GoalProgress {
        let workouts = goal.timeframe == .custom
            ? appState.workoutStore.workouts
            : appState.workoutStore.todaysWorkouts
        return appState.goalManager.progress(for: goal, workouts: workouts, settings: appState.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline)
                    Text("\(goal.timeframe.displayName) · \(goal.type.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(progress.percentageInt)%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(progress.percentage >= 1.0 ? .green : .primary)
            }

            ProgressView(value: progress.percentage)
                .tint(progress.percentage >= 1.0 ? .green : .blue)

            HStack {
                Text("\(progress.formattedCurrent) / \(progress.formattedTarget) \(goal.unit.symbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(goal.isActive ? "Pause" : "Resume") {
                    appState.goalManager.toggleGoal(id: goal.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("Delete") {
                    appState.goalManager.deleteGoal(id: goal.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Daily Walking Goal"
    @State private var type: GoalType = .distance
    @State private var target: Double = 5.0
    @State private var timeframe: GoalTimeframe = .daily

    private var unit: GoalUnit {
        GoalUnit.defaultUnit(for: type, metric: appState.settings.useMetric)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Goal")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("Name", text: $name)

                Picker("Type", selection: $type) {
                    ForEach(GoalType.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }

                Picker("Timeframe", selection: $timeframe) {
                    ForEach(GoalTimeframe.allCases.filter { $0 != .custom }, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }

                HStack {
                    Text("Target")
                    Spacer()
                    TextField("", value: $target, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text(unit.symbol)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") {
                    let goal = Goal(
                        name: name,
                        type: type,
                        target: target,
                        unit: unit,
                        timeframe: timeframe
                    )
                    appState.goalManager.addGoal(goal)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

// MARK: - Journey Picker

struct JourneyPickerSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var months: Int = 4

    var body: some View {
        VStack(spacing: 16) {
            Text("Start a Journey")
                .font(.title2)
                .fontWeight(.bold)

            Text("Pick a real-world trail to walk on your treadmill. Track your progress over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(JourneyPreset.allPresets) { preset in
                        Button(action: {
                            let goal = appState.goalManager.createJourneyGoal(
                                from: preset,
                                useMetric: appState.settings.useMetric,
                                months: months
                            )
                            appState.goalManager.addGoal(goal)
                            dismiss()
                        }) {
                            HStack {
                                Text(preset.emoji)
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                        .font(.headline)
                                    Text("\(String(format: "%.0f", preset.distanceMiles)) mi · \(preset.description)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(.background.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Complete in")
                Picker("Months", selection: $months) {
                    ForEach([2, 3, 4, 6, 8, 12], id: \.self) { m in
                        Text("\(m) months").tag(m)
                    }
                }
                .frame(width: 120)
            }
            .font(.caption)

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 420, height: 480)
    }
}
