import SwiftUI
import Charts

struct DashboardView: View {
    let appState: AppState
    @State private var selectedPeriod: StatsPeriod = .day
    @State private var chartDays: Int = 7

    private var stats: PeriodStats { appState.statsCalculator.stats(for: selectedPeriod) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top: Progress ring + streak
                HStack(spacing: 24) {
                    todayProgressRing
                    streakDisplay
                    Spacer()
                }
                .padding(.horizontal)

                // Journey progress
                journeyProgressSection
                    .padding(.horizontal)

                // Period selector + stats cards
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(StatsPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)

                    statsCards
                }
                .padding(.horizontal)

                // Chart
                chartSection
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Today's Progress Ring

    @ViewBuilder
    private var todayProgressRing: some View {
        let dailyGoal = appState.goalManager.activeGoals.first(where: { $0.timeframe == .daily })
        let progress: Double = {
            if let goal = dailyGoal {
                return appState.goalManager.progress(
                    for: goal,
                    workouts: appState.workoutStore.todaysWorkouts,
                    settings: appState.settings
                ).percentage
            }
            return 0
        }()

        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            if let goal = dailyGoal {
                let prog = appState.goalManager.progress(
                    for: goal,
                    workouts: appState.workoutStore.todaysWorkouts,
                    settings: appState.settings
                )
                Text("\(prog.formattedCurrent) / \(prog.formattedTarget) \(goal.unit.symbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Streak

    @ViewBuilder
    private var streakDisplay: some View {
        let current = appState.statsCalculator.currentStreak
        let best = appState.statsCalculator.bestStreak

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("🔥")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("\(current)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("day streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if best > current {
                Text("Best: \(best) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Journey Progress

    @ViewBuilder
    private var journeyProgressSection: some View {
        if let journey = appState.goalManager.activeGoals.first(where: { $0.timeframe == .custom }) {
            let prog = appState.goalManager.progress(
                for: journey,
                workouts: appState.workoutStore.workouts,
                settings: appState.settings
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(journey.name)
                        .font(.headline)
                    Spacer()
                    Text("\(prog.formattedCurrent) / \(prog.formattedTarget) \(journey.unit.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: prog.percentage)
                    .tint(.orange)
                    .scaleEffect(y: 2)

                if let nudge = appState.goalManager.nudgeText(
                    for: journey,
                    workouts: appState.workoutStore.workouts,
                    settings: appState.settings
                ) {
                    Text(nudge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Stats Cards

    @ViewBuilder
    private var statsCards: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Distance",
                value: appState.settings.distanceString(stats.distance),
                icon: "map",
                color: .blue
            )
            StatCard(
                title: "Time",
                value: stats.formattedDuration,
                icon: "clock",
                color: .green
            )
            StatCard(
                title: "Steps",
                value: "\(stats.steps)",
                icon: "shoeprints.fill",
                color: .orange
            )
            StatCard(
                title: "Calories",
                value: "\(stats.calories) kcal",
                icon: "flame",
                color: .red
            )
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Distance")
                    .font(.headline)
                Spacer()
                Picker("Days", selection: $chartDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            let data = appState.statsCalculator.dailyDistances(last: chartDays)
            let useMetric = appState.settings.useMetric

            Chart(data) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Distance", useMetric ? item.distance : item.distance / 1.60934)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
            }
            .chartYAxisLabel(appState.settings.distanceUnitShort)
            .frame(height: 180)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
