import SwiftUI

struct MenuBarView: View {
    let appState: AppState

    private var state: TreadmillState { appState.treadmillState }
    private var bleManager: TreadmillBLEManager { appState.bleManager }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Section: Treadmill Controls
            treadmillControlsSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            // MARK: - Middle Section: Current Session
            if state.isRunning || appState.workoutRecorder.isRecording {
                currentSessionSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
            }

            // MARK: - Bottom Section: Today's Progress
            todayProgressSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // MARK: - Footer
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // MARK: - Toast
            if appState.workoutRecorder.showSavedToast {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Workout saved!")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.vertical, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.2), value: state.isRunning)
        .animation(.easeInOut(duration: 0.2), value: appState.workoutRecorder.showSavedToast)
    }

    // MARK: - Treadmill Controls

    @ViewBuilder
    private var treadmillControlsSection: some View {
        VStack(spacing: 10) {
            // Connection status
            HStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(state.connectionStatus.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if state.isRunning {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if state.connectionStatus == .connected {
                // Large speed display
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", state.currentSpeed))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("km/h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // +/- and preset buttons
                HStack(spacing: 6) {
                    Button(action: { adjustSpeed(-0.5) }) {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ForEach([2.0, 3.0, 4.0, 5.0], id: \.self) { speed in
                        Button(String(format: "%.0f", speed)) {
                            state.targetSpeed = speed
                            bleManager.setSpeed(speed)
                        }
                        .buttonStyle(.bordered)
                        .tint(speed == state.targetSpeed ? .accentColor : nil)
                        .controlSize(.small)
                    }

                    Button(action: { adjustSpeed(0.5) }) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Start/Pause/Stop
                HStack(spacing: 8) {
                    if state.isRunning {
                        Button(action: { bleManager.pauseTreadmill() }) {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button(action: { bleManager.stopTreadmill() }) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.regular)
                    } else {
                        Button(action: {
                            let speed = state.targetSpeed > 0 ? state.targetSpeed : 3.0
                            bleManager.startTreadmill(speed: speed)
                        }) {
                            Label("Start Walking", systemImage: "figure.walk")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.regular)
                    }
                }
            } else if state.connectionStatus == .scanning {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for treadmill...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(action: { bleManager.startScanning() }) {
                    Label("Connect Treadmill", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Current Session

    @ViewBuilder
    private var currentSessionSection: some View {
        HStack(spacing: 0) {
            miniStat(icon: "speedometer", value: state.formattedSpeed)
            Spacer()
            miniStat(icon: "map", value: state.formattedDistance)
            Spacer()
            miniStat(icon: "clock", value: state.formattedDuration)
            Spacer()
            miniStat(icon: "flame", value: "\(state.calories)")
            Spacer()
            miniStat(icon: "shoeprints.fill", value: "\(state.steps)")
        }
    }

    private func miniStat(icon: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    // MARK: - Today's Progress

    @ViewBuilder
    private var todayProgressSection: some View {
        VStack(spacing: 8) {
            if let goal = appState.goalManager.activeGoals.first(where: { $0.timeframe == .daily }) {
                let progress = appState.goalManager.progress(
                    for: goal,
                    workouts: appState.workoutStore.todaysWorkouts,
                    settings: appState.settings
                )

                HStack {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress.percentage))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(progress.percentageInt)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(progress.formattedCurrent) / \(progress.formattedTarget) \(goal.unit.symbol) today")
                            .font(.caption)
                            .fontWeight(.medium)

                        if let nudge = appState.goalManager.nudgeText(for: goal, workouts: appState.workoutStore.todaysWorkouts, settings: appState.settings) {
                            Text(nudge)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
            } else {
                // No daily goal set — show today's totals
                let today = appState.statsCalculator.todayStats
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(appState.settings.distanceString(today.distance)) · \(today.formattedDuration)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            // Streak
            let streak = appState.statsCalculator.currentStreak
            if streak > 0 {
                HStack {
                    Text("🔥 \(streak) day streak")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
            }

            // Journey progress
            if let journey = appState.goalManager.activeGoals.first(where: { $0.timeframe == .custom }) {
                let prog = appState.goalManager.progress(
                    for: journey,
                    workouts: appState.workoutStore.workouts,
                    settings: appState.settings
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(journey.name)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(prog.percentageInt)%")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: prog.percentage)
                        .tint(.orange)
                    if let nudge = appState.goalManager.nudgeText(for: journey, workouts: appState.workoutStore.workouts, settings: appState.settings) {
                        Text(nudge)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerSection: some View {
        HStack {
            Button(action: { openMainWindow() }) {
                Label("Open DeskRun", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()

            Button(action: { openMainWindow() }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private var connectionColor: Color {
        switch state.connectionStatus {
        case .disconnected: return .gray
        case .scanning: return .orange
        case .connecting: return .yellow
        case .connected: return .green
        case .error: return .red
        }
    }

    private func adjustSpeed(_ delta: Double) {
        let newSpeed = max(0.5, min(6.0, state.targetSpeed + delta))
        state.targetSpeed = newSpeed
        bleManager.setSpeed(newSpeed)
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title.contains("DeskRun") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open a new window if none exist
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
