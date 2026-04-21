import SwiftUI

/// Compact one-row walk control embedded in `JourneyMapView`.
///
/// Unlike the Free Walk card on the dashboard, this surface is subordinate to
/// the map — it gives just enough control (speed, start/pause/stop) without
/// duplicating the live stats shown in the StatsBar below.
///
/// On Start it marks the session as a journey walk so miles accrue to the
/// active journey. Disabled while the journey is paused (resume lives in
/// Settings › Adventure Mode).
struct JourneyWalkCard: View {
    let appState: AppState

    private var state: TreadmillState { appState.treadmillState }
    private var bleManager: TreadmillBLEManager { appState.bleManager }
    private var settings: AppSettings { appState.settings }
    private var recorder: WorkoutRecorder { appState.workoutRecorder }
    private var walkSession: WalkSession { appState.walkSession }
    private var activeJourney: JourneyState? { appState.journeyStore.active }
    private var isPaused: Bool { activeJourney.map { !$0.isTrackingEnabled } ?? false }

    var body: some View {
        HStack(spacing: 10) {
            switch state.connectionStatus {
            case .connected:
                connectedRow
            case .scanning, .connecting:
                scanningRow
            case .disconnected, .error:
                disconnectedRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrailColor.parchment)
        .overlay(
            Rectangle()
                .strokeBorder(TrailColor.darkEarth.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Connected row

    private var connectedRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(settings.speedValueString(displayedSpeed))
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                    .foregroundStyle(TrailColor.darkEarth)
                    .monospacedDigit()
                Text(settings.speedUnitShort)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(TrailColor.text.opacity(0.6))
            }
            .frame(minWidth: 64, alignment: .leading)

            presetRow

            Spacer(minLength: 8)

            if recorder.isRecording {
                sessionMetrics
            }

            actionRow

            statusBadge
        }
    }

    private var sessionMetrics: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(settings.distanceString(recorder.sessionDistance))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(TrailColor.darkEarth)
                .monospacedDigit()
            Text(formatDuration(recorder.sessionDuration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(TrailColor.text.opacity(0.65))
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var presetRow: some View {
        HStack(spacing: 4) {
            Button(action: { adjustSpeed(-settings.speedIncrement) }) {
                Image(systemName: "minus").frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            ForEach(settings.speedPresets, id: \.self) { displaySpeed in
                Button(settings.speedPresetLabel(displaySpeed)) {
                    let speed = settings.kilometersPerHour(fromDisplaySpeed: displaySpeed)
                    state.targetSpeed = speed
                    bleManager.setSpeed(speed)
                }
                .buttonStyle(.bordered)
                .tint(settings.isSelectedSpeedPreset(state.targetSpeed, displayPreset: displaySpeed) ? TrailColor.coral : nil)
                .controlSize(.mini)
            }

            Button(action: { adjustSpeed(settings.speedIncrement) }) {
                Image(systemName: "plus").frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if state.isRunning {
            Button(action: { bleManager.pauseTreadmill() }) {
                Image(systemName: "pause.fill")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Pause walk")

            Button(action: { bleManager.stopTreadmill() }) {
                Image(systemName: "stop.fill")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrailColor.coral)
            .controlSize(.small)
            .help("Stop walk")
        } else {
            Button(action: startJourneyWalk) {
                Label("Start", systemImage: "figure.walk")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .buttonStyle(.borderedProminent)
            .tint(isPaused ? TrailColor.desertSand : TrailColor.forestGreen)
            .controlSize(.small)
            .disabled(isPaused || activeJourney == nil)

            if recorder.isRecording {
                Button(action: { recorder.stopRecording() }) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Save walk")
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor)
            .tracking(1)
            .frame(minWidth: 64, alignment: .trailing)
    }

    private var statusText: String {
        if isPaused { return "PAUSED" }
        if recorder.isRecording { return "● REC" }
        return "READY"
    }

    private var statusColor: Color {
        if isPaused { return TrailColor.desertSand }
        if recorder.isRecording { return TrailColor.coral }
        return TrailColor.text.opacity(0.5)
    }

    // MARK: - Scanning / Disconnected

    private var scanningRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text("SCANNING FOR TREADMILL…")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TrailColor.text.opacity(0.65))
                .tracking(1)
            Spacer()
        }
    }

    private var disconnectedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(TrailColor.text.opacity(0.5))
            Text("TREADMILL DISCONNECTED")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TrailColor.text.opacity(0.65))
                .tracking(1)
            Spacer()
            Button("Connect") { bleManager.startScanning() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    /// The big speed readout reflects the user's intent (target) whenever they've
    /// set one. Current speed only shows when the target is still 0 — otherwise
    /// ramp-up/ramp-down makes the display lag behind the preset the user just
    /// tapped, which reads as "I pressed 1.5 but it says 2.4."
    private var displayedSpeed: Double {
        state.targetSpeed > 0 ? state.targetSpeed : state.currentSpeed
    }

    private func startJourneyWalk() {
        guard let journey = activeJourney else { return }
        walkSession.markJourneyWalk(id: journey.id)
        let speed = state.targetSpeed > 0 ? state.targetSpeed : settings.defaultSpeed
        bleManager.startTreadmill(speed: speed)
    }

    private func adjustSpeed(_ delta: Double) {
        let newKmh = max(settings.minimumControlSpeed,
                         min(settings.maximumControlSpeed, state.targetSpeed + delta))
        state.targetSpeed = newKmh
        bleManager.setSpeed(newKmh)
    }
}
