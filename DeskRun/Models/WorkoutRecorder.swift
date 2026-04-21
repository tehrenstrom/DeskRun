import Foundation
import Observation

@Observable
class WorkoutRecorder {
    private let treadmillState: TreadmillState
    private let workoutStore: WorkoutStore

    var isRecording: Bool = false
    var showSavedToast: Bool = false

    private var currentWorkoutStart: Date?
    private var lastNonZeroSpeed: Date?
    private var zeroSpeedTimer: Timer?

    private static let stopDelay: TimeInterval = 30  // seconds of zero speed before auto-stop

    init(treadmillState: TreadmillState, workoutStore: WorkoutStore) {
        self.treadmillState = treadmillState
        self.workoutStore = workoutStore
    }

    /// Call this on every BLE state update
    func handleStateUpdate() {
        let speed = treadmillState.currentSpeed

        if speed > 0 {
            lastNonZeroSpeed = Date()
            zeroSpeedTimer?.invalidate()
            zeroSpeedTimer = nil

            if !isRecording {
                startRecording()
            }
        } else if isRecording {
            // Speed is zero while recording — start countdown
            if zeroSpeedTimer == nil {
                zeroSpeedTimer = Timer.scheduledTimer(withTimeInterval: Self.stopDelay, repeats: false) { [weak self] _ in
                    self?.stopRecording()
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        currentWorkoutStart = Date()
        print("🏃 Workout recording started")
    }

    func stopRecording() {
        guard isRecording, let startDate = currentWorkoutStart else { return }

        zeroSpeedTimer?.invalidate()
        zeroSpeedTimer = nil

        let workout = WorkoutRecord(
            startDate: startDate,
            endDate: Date(),
            distance: treadmillState.distance,
            steps: treadmillState.steps,
            calories: treadmillState.calories,
            duration: treadmillState.duration,
            averageSpeed: treadmillState.duration > 0
                ? treadmillState.distance / (treadmillState.duration / 3600)
                : 0
        )

        // Only save if meaningful (at least 1 minute or 0.01 km)
        if workout.duration >= 60 || workout.distance >= 0.01 {
            workoutStore.addWorkout(workout)
            print("💾 Workout saved: \(workout.formattedDistance) in \(workout.formattedDuration)")

            // Show toast
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.showSavedToast = false
            }
        }

        isRecording = false
        currentWorkoutStart = nil
    }
}
