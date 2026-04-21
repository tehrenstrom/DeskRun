import SwiftUI

struct SettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            // Treadmill section
            Section("Treadmill") {
                HStack {
                    Text("Default Speed")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.settings.defaultSpeed },
                        set: { appState.settings.defaultSpeed = $0; appState.saveSettings() }
                    ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    Text("km/h")
                        .foregroundStyle(.secondary)
                }

                Picker("Units", selection: Binding(
                    get: { appState.settings.useMetric },
                    set: { appState.settings.useMetric = $0; appState.saveSettings() }
                )) {
                    Text("Kilometers").tag(true)
                    Text("Miles").tag(false)
                }

                HStack {
                    Circle()
                        .fill(appState.treadmillState.connectionStatus == .connected ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(appState.treadmillState.connectionStatus.rawValue)
                }
            }

            // Notifications section
            Section("Notifications") {
                Toggle("Notifications Enabled", isOn: Binding(
                    get: { appState.settings.notificationsEnabled },
                    set: { appState.settings.notificationsEnabled = $0; appState.saveSettings() }
                ))

                if appState.settings.notificationsEnabled {
                    Toggle("Morning Motivation", isOn: Binding(
                        get: { appState.settings.morningMotivation },
                        set: { appState.settings.morningMotivation = $0; appState.saveSettings() }
                    ))

                    Toggle("Goal Nudges", isOn: Binding(
                        get: { appState.settings.goalNudges },
                        set: { appState.settings.goalNudges = $0; appState.saveSettings() }
                    ))

                    Toggle("Streak Alerts", isOn: Binding(
                        get: { appState.settings.streakAlerts },
                        set: { appState.settings.streakAlerts = $0; appState.saveSettings() }
                    ))

                    Toggle("Milestone Celebrations", isOn: Binding(
                        get: { appState.settings.milestoneAlerts },
                        set: { appState.settings.milestoneAlerts = $0; appState.saveSettings() }
                    ))

                    Toggle("Weekly Summary", isOn: Binding(
                        get: { appState.settings.weeklySummary },
                        set: { appState.settings.weeklySummary = $0; appState.saveSettings() }
                    ))

                    Toggle("Idle Nudges", isOn: Binding(
                        get: { appState.settings.idleNudges },
                        set: { appState.settings.idleNudges = $0; appState.saveSettings() }
                    ))

                    HStack {
                        Text("Quiet Hours")
                        Spacer()
                        Picker("Start", selection: Binding(
                            get: { appState.settings.quietHoursStart },
                            set: { appState.settings.quietHoursStart = $0; appState.saveSettings() }
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)
                        Text("to")
                        Picker("End", selection: Binding(
                            get: { appState.settings.quietHoursEnd },
                            set: { appState.settings.quietHoursEnd = $0; appState.saveSettings() }
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)
                    }

                    HStack {
                        Text("Max notifications per day")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appState.settings.maxNotificationsPerDay },
                            set: { appState.settings.maxNotificationsPerDay = $0; appState.saveSettings() }
                        )) {
                            ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .frame(width: 60)
                    }
                }
            }

            // About section
            Section("About") {
                HStack {
                    Text("DeskRun")
                    Spacer()
                    Text("v1.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Data location")
                    Spacer()
                    Text("~/Library/Application Support/DeskRun/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
